import Foundation
import SwiftData
import Observation
import UIKit

@Observable
final class ChatViewModel {
    let conversation: Conversation
    private let engineProvider: () -> LLMEngine?
    private let context: ModelContext
    private var task: Task<Void, Never>?

    var isTyping = false
    /// True while the persona hasn't "read" the latest message yet (typing dots stay hidden).
    var awaitingRead = false
    var showTyping: Bool { isTyping && !awaitingRead }
    var errorMessage: String?

    init(conversation: Conversation, engineProvider: @escaping () -> LLMEngine?, context: ModelContext) {
        self.conversation = conversation
        self.engineProvider = engineProvider
        self.context = context
    }

    func send(_ text: String, image: UIImage? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || image != nil, !isTyping, conversation.persona != nil else { return }
        guard engineProvider() != nil else {
            errorMessage = "The model is still loading. Try again in a moment."
            return
        }
        errorMessage = nil
        append(role: .user, text: trimmed, image: image)
        Haptics.tap()
        generate(markRead: true)
    }

    /// Adds or clears an emoji reaction on a message.
    func react(to message: Message, with emoji: String) {
        message.reaction = message.reaction == emoji ? nil : emoji
        try? context.save()
        Haptics.pop()
    }

    /// Starts a game or role-play; the persona makes the first move.
    func startGame(_ game: ChatGame) {
        guard !isTyping, conversation.persona != nil else { return }
        guard engineProvider() != nil else {
            errorMessage = "The model is still loading. Try again in a moment."
            return
        }
        errorMessage = nil
        conversation.game = game
        conversation.gameSeed = game.randomSeed()
        try? context.save()
        generate(cue: game.startCue(seed: conversation.gameSeed))
    }

    func endGame() {
        conversation.game = nil
        conversation.gameSeed = nil
        try? context.save()
    }

    /// Asks the model for a reply to the current history. `cue` is a hidden instruction that isn't saved.
    private func generate(cue: String? = nil, markRead: Bool = false) {
        guard let persona = conversation.persona, let engine = engineProvider() else { return }
        let turns = PromptBuilder.turns(
            persona: persona,
            memories: persona.memories.sorted { $0.createdAt > $1.createdAt }.map(\.text),
            summary: conversation.summary,
            history: conversation.sortedMessages,
            game: conversation.game,
            gameSeed: conversation.gameSeed,
            cue: cue
        )

        isTyping = true
        awaitingRead = markRead
        let params = GenerationParams.current
        task = Task {
            defer { isTyping = false; awaitingRead = false }
            do {
                if markRead {
                    // A short human pause, then "Seen", then the typing dots.
                    try await Task.sleep(for: .milliseconds(Int.random(in: 500...1100)))
                    markMessagesRead()
                    awaitingRead = false
                    try await Task.sleep(for: .milliseconds(250))
                }
                var raw = ""
                for try await chunk in engine.stream(turns: turns, params: params) {
                    raw += chunk
                }
                let bubbles = ReplyFormatter.bubbles(from: raw, personaName: persona.name)
                for (i, bubble) in bubbles.enumerated() {
                    try await Task.sleep(for: ReplyFormatter.typingDelay(for: bubble))
                    append(role: .assistant, text: bubble)
                    if i < bubbles.count - 1 { isTyping = true }
                }
            } catch is CancellationError {
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markMessagesRead() {
        let unread = conversation.messages.filter { $0.role == .user && !$0.seen }
        unread.forEach { $0.seen = true }
        // Sometimes the persona reacts to what you said.
        if let last = unread.max(by: { $0.createdAt < $1.createdAt }),
           !last.text.isEmpty, last.reaction == nil, Int.random(in: 0..<4) == 0 {
            last.reaction = ["❤️", "😂", "👍"].randomElement()
            Haptics.soft()
        }
        try? context.save()
    }

    func stop() {
        task?.cancel()
        isTyping = false
    }

    private func append(role: MessageRole, text: String, image: UIImage? = nil) {
        let message = Message(role: role, text: text)
        message.imageData = image?.akariJPEG()
        if role == .assistant { Haptics.soft() }
        message.conversation = conversation
        context.insert(message)
        conversation.updatedAt = Date()
        try? context.save()
    }
}
