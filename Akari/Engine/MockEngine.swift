import Foundation

/// Canned, casual replies so the UI can be developed in the Simulator without a model.
struct MockEngine: LLMEngine {
    private static let replies = [
        "haha okay that's actually kinda funny\nwhat made you think of that?",
        "wait really?? tell me more",
        "ugh i know the feeling\nlong day?",
        "lol no way. i would've done the exact same thing",
        "hmm honestly not sure. what do you think?",
    ]

    func stream(turns: [ChatTurn], params: GenerationParams) -> AsyncThrowingStream<String, Error> {
        let reply = Self.replies.randomElement() ?? "hey"
        return AsyncThrowingStream { continuation in
            let task = Task {
                try? await Task.sleep(for: .milliseconds(400))
                for word in reply.split(separator: " ", omittingEmptySubsequences: false) {
                    if Task.isCancelled { break }
                    continuation.yield(String(word) + " ")
                    try? await Task.sleep(for: .milliseconds(40))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
