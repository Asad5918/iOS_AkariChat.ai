import Foundation
import SwiftData

enum MessageRole: String, Codable {
    case user, assistant
}

enum PersonaLanguage: String, CaseIterable, Identifiable {
    case english, hinglish
    var id: String { rawValue }
    var title: String {
        switch self {
        case .english: "English"
        case .hinglish: "Hinglish"
        }
    }
}

@Model
final class Persona {
    var id: UUID = UUID()
    var name: String
    var emoji: String
    var tagline: String
    /// Who they are: age, background, personality.
    var backstory: String
    /// How they text: tone, length, quirks.
    var speakingStyle: String
    var createdAt: Date = Date()
    /// Raw value of `PersonaLanguage` (stored as a string so existing data migrates with a default).
    /// Optional sample exchanges ("User: ..." / "Name: ...") that lock in the voice.
    var exampleChats: String = ""
    var languageRaw: String = PersonaLanguage.english.rawValue

    var language: PersonaLanguage {
        get { PersonaLanguage(rawValue: languageRaw) ?? .english }
        set { languageRaw = newValue.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Conversation.persona)
    var conversations: [Conversation] = []

    @Relationship(deleteRule: .cascade, inverse: \MemoryFact.persona)
    var memories: [MemoryFact] = []

    init(name: String, emoji: String, tagline: String, backstory: String, speakingStyle: String,
         exampleChats: String = "", language: PersonaLanguage = .english) {
        self.exampleChats = exampleChats
        self.languageRaw = language.rawValue
        self.name = name
        self.emoji = emoji
        self.tagline = tagline
        self.backstory = backstory
        self.speakingStyle = speakingStyle
    }
}

@Model
final class Conversation {
    var id: UUID = UUID()
    var persona: Persona?
    var summary: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    /// Raw value of the active `ChatGame`, nil when just chatting.
    var gameRaw: String?
    /// Secret or role chosen by the app for the active game (e.g. what 20 Questions is thinking of).
    var gameSeed: String?

    var game: ChatGame? {
        get { gameRaw.flatMap(ChatGame.init(rawValue:)) }
        set { gameRaw = newValue?.rawValue }
    }

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(persona: Persona) {
        self.persona = persona
    }

    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}

@Model
final class Message {
    var id: UUID = UUID()
    var roleRaw: String
    var text: String
    var createdAt: Date
    var conversation: Conversation?
    /// Emoji reaction on this message, if any.
    var reaction: String?
    /// Set once the persona has "read" a user message.
    var seen: Bool = false
    /// Photo attached to the message (JPEG).
    @Attribute(.externalStorage) var imageData: Data?

    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    init(role: MessageRole, text: String, createdAt: Date = Date()) {
        self.roleRaw = role.rawValue
        self.text = text
        self.createdAt = createdAt
    }
}

@Model
final class MemoryFact {
    var id: UUID = UUID()
    var text: String
    var createdAt: Date = Date()
    var persona: Persona?

    init(text: String) {
        self.text = text
    }
}
