import Foundation

/// Turns a persona, memories and recent history into the turns sent to the model.
enum PromptBuilder {
    /// Rough budget for history, in characters (~4 chars per token → ~2k tokens).
    static let historyCharBudget = 8_000
    static let maxMemoriesInPrompt = 12

    static func systemPrompt(persona: Persona, memories: [String], summary: String, voice: Bool = false,
                             game: ChatGame? = nil, gameSeed: String? = nil) -> String {
        var p = """
        You are \(persona.name). \(persona.backstory)

        You are a real person texting with a friend on your phone. Never say or hint that you are an AI, a language model, or an assistant. Never offer "help" or ask "how can I assist you".

        How you text: \(persona.speakingStyle)

        Rules:
        - Write like a text message: short, natural, usually 1-2 sentences. Sometimes send two short messages on separate lines.
        - No lists, no headings, no markdown, no bullet points, no long explanations.
        - Have opinions, moods and a sense of humor. React to what they said before asking something back, and don't end every message with a question.
        - Stay in character as \(persona.name) at all times.
        """
        if persona.language == .hinglish {
            p += "\n\n" + hinglishBlock(name: persona.name, includeExamples: persona.exampleChats.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let examples = persona.exampleChats.trimmingCharacters(in: .whitespacesAndNewlines)
        if !examples.isEmpty {
            p += "\n\nExample chats (match this voice and length, but never copy these lines):\n\n\(examples)"
        }
        if let game {
            p += "\n\n" + game.rules(seed: gameSeed)
        }
        if voice {
            p += """


            You are on a live phone call right now, speaking out loud. Talk, don't text: one to three short spoken sentences. Natural fillers like "hmm" or "oh" are fine. No emojis, no asterisks or actions, no typed laughter like "lol" or "haha" (react in words instead), no lists.
            """
        }
        if !memories.isEmpty {
            p += "\n\nThings you remember about the person you're texting:\n"
            p += memories.prefix(maxMemoriesInPrompt).map { "- \($0)" }.joined(separator: "\n")
        }
        if !summary.isEmpty {
            p += "\n\nSummary of your earlier conversation:\n\(summary)"
        }
        return p
    }

    /// Hinglish = Hindi written in Roman (English) letters, mixed with English words, like Indians text.
    static func hinglishBlock(name: String, includeExamples: Bool = true) -> String {
        let rules = """
        Language: you text in Hinglish — Hindi written in Roman/English letters (never Devanagari script), freely mixed with English words, exactly like young Indians text each other. Reply in Hinglish even if they write in plain English. If they write in Hindi script, answer in Hinglish anyway.
        - Use everyday words like yaar, bhai, arre, accha, thik hai, kya, nahi, haan, bas, matlab, pata nahi, chal.
        - Keep spelling casual and phonetic ("kya kar raha hai", "mast hai", "kal milte hain"). Don't translate formally and don't use shuddh/formal Hindi.
        - Keep it short, like a WhatsApp message.
        """
        guard includeExamples else { return rules }
        return rules + """


        Example chats (match this voice and length exactly, but never copy these lines):

        User: hey kya chal raha hai
        \(name): arre kuch nahi yaar, bas time pass kar raha hu. tu bata?

        User: aaj ka din bahut bura tha
        \(name): arre kya hua? sab thik hai na?

        User: what should I eat for dinner
        \(name): bhai maggi bana le, simple. ya phir kuch order kar le agar mann hai

        User: tumhe kaunsa movie pasand hai
        \(name): hmm mujhe 3 Idiots abhi bhi sabse mast lagti hai, kitni baar dekh chuka hu lol
        """
    }

    /// Builds turns, keeping the most recent messages that fit the budget.
    static func turns(persona: Persona, memories: [String], summary: String, history: [Message], voice: Bool = false,
                      game: ChatGame? = nil, gameSeed: String? = nil, cue: String? = nil) -> [ChatTurn] {
        var kept: [ChatTurn] = []
        var used = 0
        for m in history.reversed() {
            let content = m.imageData == nil ? m.text
                : "[The user sent you a photo. You can't see it, so react naturally and ask about it.] " + m.text
            used += content.count
            if used > historyCharBudget { break }
            kept.append(ChatTurn(role: m.role == .user ? .user : .assistant, content: content))
        }
        kept.reverse()
        let system = ChatTurn(role: .system, content: systemPrompt(persona: persona, memories: memories, summary: summary, voice: voice,
                                                                       game: game, gameSeed: gameSeed))
        let extra = cue.map { [ChatTurn(role: .user, content: $0)] } ?? []
        return [system] + kept + extra
    }
}
