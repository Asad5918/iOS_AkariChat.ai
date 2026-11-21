import Foundation

struct ChatTurn: Sendable {
    enum Role: String, Sendable { case system, user, assistant }
    let role: Role
    let content: String
}

struct GenerationParams: Sendable {
    var temperature: Float = 0.85
    var topP: Float = 0.9
    var repetitionPenalty: Float = 1.1
    var maxTokens: Int = 160

    static let human = GenerationParams()

    /// UserDefaults keys shared with `SettingsView` (via @AppStorage).
    enum Keys {
        static let temperature = "gen.temperature"
        static let topP = "gen.topP"
        static let repetitionPenalty = "gen.repetitionPenalty"
        static let maxTokens = "gen.maxTokens"
    }

    /// Current user-tuned parameters, falling back to the humanizing defaults.
    static var current: GenerationParams {
        let d = UserDefaults.standard
        var p = GenerationParams()
        if d.object(forKey: Keys.temperature) != nil { p.temperature = Float(d.double(forKey: Keys.temperature)) }
        if d.object(forKey: Keys.topP) != nil { p.topP = Float(d.double(forKey: Keys.topP)) }
        if d.object(forKey: Keys.repetitionPenalty) != nil { p.repetitionPenalty = Float(d.double(forKey: Keys.repetitionPenalty)) }
        if d.object(forKey: Keys.maxTokens) != nil { p.maxTokens = d.integer(forKey: Keys.maxTokens) }
        return p
    }
}

/// Abstraction over any text-generation backend (MLX on-device, llama.cpp, a Mac/Ollama server, a mock).
protocol LLMEngine: Sendable {
    /// Streams generated text chunks for the given conversation.
    func stream(turns: [ChatTurn], params: GenerationParams) -> AsyncThrowingStream<String, Error>
}
