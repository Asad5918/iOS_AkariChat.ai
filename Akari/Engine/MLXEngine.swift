import Foundation
import MLXLLM
import MLXLMCommon

/// Runs a loaded MLX model on-device. Stateless per call: each generation builds a fresh
/// `ChatSession` from the system prompt + history that `PromptBuilder` produced.
nonisolated final class MLXEngine: LLMEngine, @unchecked Sendable {
    private let container: ModelContainer
    private let foldSystemPrompt: Bool

    /// - Parameter foldSystemPrompt: for chat templates without a system role (e.g. Gemma 2), the
    ///   system prompt is prepended to the first user message instead.
    init(container: ModelContainer, foldSystemPrompt: Bool = false) {
        self.container = container
        self.foldSystemPrompt = foldSystemPrompt
    }

    func stream(turns: [ChatTurn], params: GenerationParams) -> AsyncThrowingStream<String, Error> {
        var system = turns.first(where: { $0.role == .system })?.content
        var messages: [Chat.Message] = turns
            .filter { $0.role != .system }
            .map { $0.role == .user ? .user($0.content) : .assistant($0.content) }

        if foldSystemPrompt, let sys = system, let first = messages.firstIndex(where: { $0.role == .user }) {
            messages[first] = .user(sys + "\n\n" + messages[first].content)
            system = nil
        }

        let generate = GenerateParameters(
            maxTokens: params.maxTokens,
            temperature: params.temperature,
            topP: params.topP,
            repetitionPenalty: params.repetitionPenalty
        )
        let session = ChatSession(container, instructions: system, generateParameters: generate)
        return session.streamResponse(to: messages)
    }
}
