import Foundation
import AVFoundation
import Speech
import SwiftData
import Observation

/// Runs a hands-free voice call with a persona: listen → transcribe → generate → speak, on repeat.
/// Everything stays on the device (speech recognition is forced on-device when supported).
@Observable
final class VoiceCallManager: NSObject, AVSpeechSynthesizerDelegate {
    enum Phase: Equatable { case connecting, listening, thinking, speaking, ended }

    var phase: Phase = .connecting
    /// Live transcript of what the user is saying.
    var heard = ""
    /// What the persona has said this turn.
    var reply = ""
    var isMuted = false
    var speakerOn = true
    var errorMessage: String?
    private(set) var startedAt: Date?

    @ObservationIgnored private let conversation: Conversation
    @ObservationIgnored private let persona: Persona
    @ObservationIgnored private let engineProvider: () -> LLMEngine?
    @ObservationIgnored private let context: ModelContext

    @ObservationIgnored private let audioEngine = AVAudioEngine()
    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    @ObservationIgnored private var recognizer: SFSpeechRecognizer?
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var recognitionTask: SFSpeechRecognitionTask?
    @ObservationIgnored private var silenceTask: Task<Void, Never>?
    @ObservationIgnored private var generateTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var pendingUtterances = 0
    @ObservationIgnored private var finishedGenerating = false
    @ObservationIgnored private var spokenText = ""

    /// How long the user must stay quiet before we treat their turn as finished.
    private let endOfSpeechDelay: Duration = .milliseconds(1300)

    init(conversation: Conversation, engineProvider: @escaping () -> LLMEngine?, context: ModelContext) {
        self.conversation = conversation
        self.persona = conversation.persona ?? Persona(name: "Friend", emoji: "🙂", tagline: "", backstory: "", speakingStyle: "")
        self.engineProvider = engineProvider
        self.context = context
        super.init()
    }

    var personaName: String { persona.name }
    var personaEmoji: String { persona.emoji }

    // MARK: - Lifecycle

    func start() async {
        guard phase == .connecting else { return }
        guard engineProvider() != nil else {
            return fail("The model isn't loaded yet. Open Settings and load one first.")
        }
        let locale = Locale(identifier: persona.language == .hinglish ? "hi-IN" : "en-US")
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            return fail("Speech recognition isn't available for this language right now.")
        }
        self.recognizer = recognizer
        guard await Self.requestPermissions() else {
            return fail("Allow microphone and speech recognition access in Settings to make calls.")
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .voiceChat)
            try session.setActive(true)
            try session.overrideOutputAudioPort(.speaker)
        } catch {
            return fail("Couldn't start audio: \(error.localizedDescription)")
        }
        synthesizer.delegate = self
        startedAt = Date()
        startListening()
    }

    func end() {
        guard phase != .ended else { return }
        phase = .ended
        generateTask?.cancel()
        synthesizer.stopSpeaking(at: .immediate)
        stopListening()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func toggleMute() {
        isMuted.toggle()
        guard phase == .listening else { return }
        if isMuted { stopListening() } else { startListening() }
    }

    func toggleSpeaker() {
        speakerOn.toggle()
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    private func fail(_ message: String) {
        errorMessage = message
        phase = .ended
    }

    // MARK: - Listening

    private func startListening() {
        guard phase != .ended, let recognizer else { return }
        phase = .listening
        guard !isMuted else { return }
        stopListening()
        heard = ""

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { req.requiresOnDeviceRecognition = true }
        request = req
        let gen = generation
        recognitionTask = Self.makeTask(recognizer: recognizer, request: req) { [weak self] text, isFinal, failed in
            Task { @MainActor in self?.handle(text: text, isFinal: isFinal, failed: failed, gen: gen) }
        }
        do {
            Self.installTap(on: audioEngine, request: req)
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            stopListening()
            fail("Couldn't open the microphone: \(error.localizedDescription)")
        }
    }

    private func stopListening() {
        generation += 1
        silenceTask?.cancel()
        recognitionTask?.cancel()
        request?.endAudio()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        request = nil
        recognitionTask = nil
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool, gen: Int) {
        guard gen == generation, phase == .listening else { return }
        if let text, !text.isEmpty {
            failures = 0
            heard = text
            scheduleEndOfSpeech(gen: gen)
            if isFinal { finishUserTurn() }
        } else if failed {
            // Recognition ends on its own after silence or a timeout; just open a fresh request.
            failures += 1
            if failures > 8 { return fail("Speech recognition stopped working. Please try again.") }
            stopListening()
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                if phase == .listening { startListening() }
            }
        }
    }

    private func scheduleEndOfSpeech(gen: Int) {
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(for: endOfSpeechDelay)
            guard !Task.isCancelled, gen == generation else { return }
            finishUserTurn()
        }
    }

    private func finishUserTurn() {
        let text = heard.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        guard !text.isEmpty else { return startListening() }
        respond(to: text)
    }

    // MARK: - Replying

    private func respond(to text: String) {
        phase = .thinking
        reply = ""
        spokenText = ""
        pendingUtterances = 0
        finishedGenerating = false
        append(role: .user, text: text)

        guard let engine = engineProvider() else {
            return fail("The model isn't loaded.")
        }
        let turns = PromptBuilder.turns(
            persona: persona,
            memories: persona.memories.sorted { $0.createdAt > $1.createdAt }.map(\.text),
            summary: conversation.summary,
            history: conversation.sortedMessages,
            voice: true,
            game: conversation.game,
            gameSeed: conversation.gameSeed
        )
        let params = GenerationParams.current

        generateTask = Task {
            var buffer = ""
            do {
                for try await chunk in engine.stream(turns: turns, params: params) {
                    buffer += chunk
                    while let sentence = Self.popSentence(&buffer) { speak(sentence) }
                }
                if !buffer.isEmpty { speak(buffer) }
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
            }
            finishedGenerating = true
            if pendingUtterances == 0 { finishTurn() }
        }
    }

    private func speak(_ raw: String) {
        let clean = ReplyFormatter.spoken(raw, personaName: persona.name)
        guard !clean.isEmpty, phase != .ended else { return }
        reply += (reply.isEmpty ? "" : " ") + clean
        spokenText = reply
        phase = .speaking

        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = voice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.03
        pendingUtterances += 1
        synthesizer.speak(utterance)
    }

    private func utteranceFinished() {
        pendingUtterances = max(0, pendingUtterances - 1)
        if pendingUtterances == 0, finishedGenerating { finishTurn() }
    }

    private func finishTurn() {
        guard phase != .ended else { return }
        if !spokenText.isEmpty { append(role: .assistant, text: spokenText) }
        startListening()
    }

    private func voice() -> AVSpeechSynthesisVoice? {
        let lang = persona.language == .hinglish ? "en-IN" : "en-US"
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return candidates.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: lang)
    }

    private func append(role: MessageRole, text: String) {
        let message = Message(role: role, text: text)
        message.conversation = conversation
        context.insert(message)
        conversation.updatedAt = Date()
        try? context.save()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.utteranceFinished() }
    }

    // MARK: - Helpers (nonisolated: these run on audio / speech threads)

    nonisolated private static func requestPermissions() async -> Bool {
        let speechOK = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        guard speechOK else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    nonisolated private static func makeTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        onResult: @escaping @Sendable (String?, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            onResult(result?.bestTranscription.formattedString, result?.isFinal ?? false, error != nil)
        }
    }

    nonisolated private static func installTap(on engine: AVAudioEngine, request: SFSpeechAudioBufferRecognitionRequest) {
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    /// Pulls the first complete sentence off the streaming buffer so speech can start before generation ends.
    private static func popSentence(_ buffer: inout String) -> String? {
        var count = 0
        var index = buffer.startIndex
        while index < buffer.endIndex {
            let c = buffer[index]
            count += 1
            let next = buffer.index(after: index)
            let endsSentence = ".?!…".contains(c) && count >= 15
                && next < buffer.endIndex && buffer[next].isWhitespace
            if endsSentence || (c == "\n" && count > 1) {
                let sentence = String(buffer[..<next])
                buffer = String(buffer[next...])
                return sentence
            }
            index = next
        }
        return nil
    }
}
