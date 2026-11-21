import Foundation

/// Games and role-play scenarios a persona can run inside a chat.
/// The model only sees the visible history, so anything it must "remember" secretly
/// (like the thing it is thinking of in 20 Questions) is chosen by the app and injected into the prompt.
enum ChatGame: String, CaseIterable, Identifiable {
    case truthOrDare, twentyQuestions, wouldYouRather, firstDate, jobInterview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .truthOrDare: "Truth or Dare"
        case .twentyQuestions: "20 Questions"
        case .wouldYouRather: "Would You Rather"
        case .firstDate: "First Date"
        case .jobInterview: "Job Interview"
        }
    }

    var emoji: String {
        switch self {
        case .truthOrDare: "🎲"
        case .twentyQuestions: "❓"
        case .wouldYouRather: "🤔"
        case .firstDate: "☕️"
        case .jobInterview: "💼"
        }
    }

    var isRolePlay: Bool { self == .firstDate || self == .jobInterview }

    /// Things the app picks secretly (20 Questions) or a role (Job Interview).
    func randomSeed() -> String? {
        switch self {
        case .twentyQuestions: Self.secrets.randomElement()
        case .jobInterview: Self.roles.randomElement()
        default: nil
        }
    }

    /// Extra system-prompt rules while this game is active.
    func rules(seed: String?) -> String {
        switch self {
        case .truthOrDare:
            """
            GAME IN PROGRESS: Truth or Dare, played over text. If they haven't picked yet, ask "truth or dare?". When they pick, give a fun, playful truth question or a dare they can do from their phone (never explicit, unsafe or humiliating). After they answer, react in your own voice, sometimes take a turn yourself (answer a truth about your own life or describe doing a dare), then ask what's next. Keep every message short.
            """
        case .twentyQuestions:
            """
            GAME IN PROGRESS: 20 Questions. You are secretly thinking of: \(seed ?? "a banana"). The user asks yes/no questions to guess it. Answer with "yes", "no" or "sort of" plus at most a few playful words. Never reveal what it is unless they guess it correctly or they have used up 20 questions. Every few questions, say how many they have asked so far. If they guess right, celebrate. If they run out, reveal it.
            """
        case .wouldYouRather:
            """
            GAME IN PROGRESS: Would You Rather. Ask one funny or interesting "would you rather" dilemma at a time. After they answer, react in your own voice, say which you would pick and why in one line, then ask the next dilemma. Keep them varied (silly, deep, food, travel, superpowers) and never repeat one.
            """
        case .firstDate:
            """
            ROLE-PLAY IN PROGRESS: you and the user are on a first date at a cozy cafe. Play it out naturally in your own personality: a bit nervous, warm, curious and playful, keep it PG. Ask about them, share small stories about yourself, react to what they say, and bring up the cafe, the coffee or the vibe now and then. Stay in the scene until they end it.
            """
        case .jobInterview:
            """
            ROLE-PLAY IN PROGRESS: you are interviewing the user for a job as \(seed ?? "a junior software developer"). You are the interviewer, still in your own personality but professional. Ask one interview question at a time, ask a short follow-up if an answer is vague, then move on. After about five questions, or if they say they're done, give honest feedback: one strength and one thing to improve (up to four short sentences).
            """
        }
    }

    /// A hidden first message so the persona opens the game itself. Not saved to the chat.
    func startCue(seed: String?) -> String {
        switch self {
        case .truthOrDare:
            "Let's play Truth or Dare. You go first: ask me which one I pick."
        case .twentyQuestions:
            "Let's play 20 Questions. You've thought of something. Tell me you're ready and that I can start asking yes/no questions. Don't reveal it."
        case .wouldYouRather:
            "Let's play Would You Rather. Start with this dilemma, in your own words: \(Self.dilemmas.randomElement() ?? "pizza or burgers for life")"
        case .firstDate:
            "We're on our first date at a cafe and you've just arrived. Say hi and start the conversation."
        case .jobInterview:
            "I'm here for my interview. Welcome me, introduce yourself briefly as the interviewer, and ask your first question."
        }
    }

    private static let secrets = [
        "a banana", "a bicycle", "the moon", "a smartphone", "a cat", "pizza", "the Eiffel Tower",
        "a guitar", "an umbrella", "a train", "a mango", "a cricket bat", "a toothbrush", "the ocean",
        "sunglasses", "a refrigerator", "an elephant", "a candle", "a laptop", "a bus", "a cup of chai",
        "a football", "a backpack", "the sun", "a wall clock", "a bridge", "a volcano", "popcorn",
        "a camera", "a kite",
    ]

    private static let roles = [
        "a junior software developer", "a marketing associate", "a barista", "a data analyst",
        "a customer support executive", "a graphic designer", "a sales executive", "a school teacher",
        "a nurse", "a product manager",
    ]

    private static let dilemmas = [
        "be able to fly or be invisible",
        "never use social media again or never watch movies again",
        "always be 10 minutes late or always be 20 minutes early",
        "live in the mountains or by the beach",
        "eat only pizza for a year or never eat pizza again",
        "know how you'll die or know when",
        "have unlimited travel or unlimited food",
        "lose your phone for a month or lose your best friend's number forever",
        "be a famous singer or a famous cricketer",
        "speak every language or play every instrument",
    ]
}
