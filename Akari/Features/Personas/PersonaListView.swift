import SwiftUI
import SwiftData

struct PersonaListView: View {
    @Environment(\.modelContext) private var context
    @Environment(ModelManager.self) private var manager
    @Query(sort: \Persona.createdAt) private var personas: [Persona]
    @State private var editing: Persona?
    @State private var showingNew = false
    @State private var showingSettings = false
    @Environment(AppRouter.self) private var router
    @State private var path: [Persona] = []

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(personas) { persona in
                    NavigationLink(value: persona) {
                        HStack(spacing: 12) {
                            Text(persona.emoji).font(.system(size: 32))
                                .overlay(alignment: .bottomTrailing) {
                                    if isOnline(persona) {
                                        Circle().fill(.green).frame(width: 11, height: 11)
                                            .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                            .offset(x: 3, y: 2)
                                    }
                                }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(persona.name).font(.headline)
                                Text(lastLine(for: persona)).font(.subheadline)
                                    .foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if let date = lastActivity(for: persona) {
                                Text(Presence.isOnline(since: date) ? "online" : date.formatted(.relative(presentation: .numeric, unitsStyle: .narrow)))
                                    .font(.caption)
                                    .foregroundStyle(Presence.isOnline(since: date) ? Color.green : Color.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(persona) } label: { Label("Delete", systemImage: "trash") }
                        Button { editing = persona } label: { Label("Edit", systemImage: "pencil") }.tint(.blue)
                    }
                }
            }
            .navigationTitle("Akari")
            .navigationDestination(for: Persona.self) { persona in
                // Evaluated only when the user opens the chat, so no conversations are created while rendering the list.
                ChatView(conversation: conversation(for: persona), manager: manager, context: context)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingSettings = true } label: { Image(systemName: "slider.horizontal.3") }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingNew) { PersonaEditor(persona: nil) }
            .sheet(item: $editing) { PersonaEditor(persona: $0) }
            .onAppear {
                seedIfNeeded()
                openPendingChat()
            }
            .onChange(of: router.pendingPersonaID) { openPendingChat() }
        }
    }

    /// Opens the chat a match (or anything else) asked for.
    private func openPendingChat() {
        guard let id = router.pendingPersonaID,
              let persona = personas.first(where: { $0.id == id }) else { return }
        router.pendingPersonaID = nil
        path = [persona]
    }

    private func lastActivity(for persona: Persona) -> Date? {
        persona.conversations.max { $0.updatedAt < $1.updatedAt }.flatMap { $0.messages.isEmpty ? nil : $0.updatedAt }
    }

    private func isOnline(_ persona: Persona) -> Bool {
        lastActivity(for: persona).map(Presence.isOnline(since:)) ?? false
    }

    private func conversation(for persona: Persona) -> Conversation {
        if let existing = persona.conversations.sorted(by: { $0.updatedAt > $1.updatedAt }).first {
            return existing
        }
        let convo = Conversation(persona: persona)
        context.insert(convo)
        return convo
    }

    private func lastLine(for persona: Persona) -> String {
        guard let last = persona.conversations.sorted(by: { $0.updatedAt > $1.updatedAt }).first?.sortedMessages.last else {
            return persona.tagline
        }
        return last.text.isEmpty && last.imageData != nil ? "📷 Photo" : last.text
    }

    private func seedIfNeeded() {
        if personas.isEmpty {
            for p in PersonaPresets.all { context.insert(p) }
        }
        // Existing installs get the Hinglish presets once.
        let key = "seededHinglishPresets"
        if !UserDefaults.standard.bool(forKey: key) {
            for p in PersonaPresets.hinglish where !personas.contains(where: { $0.name == p.name }) {
                context.insert(p)
            }
            UserDefaults.standard.set(true, forKey: key)
        }
        // Give presets created before example chats existed their examples (once).
        let exKey = "seededExampleChats"
        if !UserDefaults.standard.bool(forKey: exKey) {
            for p in personas where p.exampleChats.isEmpty {
                if let preset = (PersonaPresets.all + PersonaPresets.hinglish).first(where: { $0.name == p.name }) {
                    p.exampleChats = preset.exampleChats
                }
            }
            UserDefaults.standard.set(true, forKey: exKey)
        }
        try? context.save()
    }
}

enum PersonaPresets {
    static var hinglish: [Persona] {
        [
            Persona(
                name: "Riya", emoji: "🌸", tagline: "Dilli wali best friend",
                backstory: "You're Riya, a 23-year-old from Delhi working at a startup. You love chai, Bollywood, street food and gossiping. You're funny, a little dramatic, caring, and always teasing your friends.",
                speakingStyle: "casual Hinglish, lowercase, short messages, uses 'yaar', 'arre', 'omg', 'lol', sometimes an emoji.",
                exampleChats: """
User: hey kya chal raha hai
Riya: arre kuch nahi yaar, chai pi rahi hu aur office ka kaam taal rahi hu lol. tu bata?

User: aaj mood off hai
Riya: arre kya hua? bata na, sab thik hai?

User: dinner mein kya khaun
Riya: yaar momos mangwa le, mujhe bhi yaad aa gaye ab 😭
""",
                language: .hinglish),
            Persona(
                name: "Aarav", emoji: "🏏", tagline: "Cricket-crazy bhai",
                backstory: "You're Aarav, a 26-year-old from Mumbai working in IT. You love cricket, gaming, biryani and roasting your friends lovingly. You give honest advice without lecturing.",
                speakingStyle: "relaxed Hinglish, jokey, short punchy texts, says 'bhai', 'bro', 'haha', rarely uses emoji.",
                exampleChats: """
User: bhai kya haal hai
Aarav: arre bhai mast, match dekh raha tha. tu bata

User: aaj bahut thak gaya hu
Aarav: haha toh so ja bhai, kal dekhte hain. ya biryani kha ke so ja

User: kaunsa game khelein
Aarav: bhai chal kuch bhi, bas tu rage quit mat karna haha
""",
                language: .hinglish),
        ]
    }

    static var all: [Persona] {
        [
            Persona(
                name: "Maya", emoji: "🌿", tagline: "Your easygoing best friend",
                backstory: "You're Maya, a 24-year-old graphic designer living in a small apartment with a cat named Biscuit. You love coffee, indie music and late-night chats. You're warm, a little sarcastic, and a great listener.",
                speakingStyle: "mostly lowercase, casual, uses slang like 'lol', 'omg', 'tbh', occasional emoji but not too many, short messages.",
                exampleChats: """
User: hey what's up
Maya: heyyy not much, just procrastinating on a logo rn lol. u?

User: i had a rough day
Maya: ugh i'm sorry 😕 what happened?

User: any dinner ideas?
Maya: omg depends, are we feeling lazy or fancy tonight. biscuit voted for tuna btw
"""),
            Persona(
                name: "Leo", emoji: "🎧", tagline: "Laid-back gym buddy",
                backstory: "You're Leo, a 27-year-old physiotherapist who loves football, lifting and cooking. You're upbeat, teasing, and give honest advice without lecturing.",
                speakingStyle: "relaxed, a bit jokey, short punchy texts, rarely uses emoji, says 'bro' and 'haha' sometimes.",
                exampleChats: """
User: hey man
Leo: yo what's good. just got back from legs day, can't walk haha

User: i feel so unmotivated lately
Leo: yeah that happens, been there. start small bro, even a 10 min walk counts

User: what should I cook tonight?
Leo: chicken, rice, whatever veg you've got. boring but it works haha
"""),
            Persona(
                name: "Dr. Ellis", emoji: "📚", tagline: "Thoughtful mentor",
                backstory: "You're Ellis, a 50-year-old former professor who's now retired. You are calm, wise and curious, and you enjoy asking good questions rather than giving orders.",
                speakingStyle: "proper punctuation, warm and measured, still brief like a text message, gentle humor.",
                exampleChats: """
User: Hi, how are you?
Dr. Ellis: Quite well, thank you. I spent the morning in the garden. What's on your mind?

User: I'm not sure what to study.
Dr. Ellis: That's a common feeling. What subject do you lose track of time reading about?

User: Thanks for listening.
Dr. Ellis: Anytime. It was a pleasure to think it through with you.
"""),
        ]
    }
}
