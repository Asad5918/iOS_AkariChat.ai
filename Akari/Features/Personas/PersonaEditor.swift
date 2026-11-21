import SwiftUI
import SwiftData

struct PersonaEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let persona: Persona?

    @State private var name = ""
    @State private var emoji = "🙂"
    @State private var tagline = ""
    @State private var backstory = ""
    @State private var speakingStyle = ""
    @State private var exampleChats = ""
    @State private var language: PersonaLanguage = .english

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Emoji", text: $emoji)
                    TextField("Tagline", text: $tagline)
                }
                Section("Language") {
                    Picker("Texts in", selection: $language) {
                        ForEach(PersonaLanguage.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("Hinglish = Hindi in English letters, mixed with English.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Who they are") {
                    TextEditor(text: $backstory).frame(minHeight: 100)
                }
                Section("How they text") {
                    TextEditor(text: $speakingStyle).frame(minHeight: 80)
                }
                Section {
                    TextEditor(text: $exampleChats).frame(minHeight: 140)
                } header: {
                    Text("Example chats (optional)")
                } footer: {
                    Text("A few short exchanges in their voice, like:\nUser: hey\nName: heyy what's up")
                }
            }
            .navigationTitle(persona == nil ? "New Persona" : "Edit Persona")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let persona else { return }
                name = persona.name; emoji = persona.emoji; tagline = persona.tagline
                backstory = persona.backstory; speakingStyle = persona.speakingStyle
                language = persona.language; exampleChats = persona.exampleChats
            }
        }
    }

    private func save() {
        if let persona {
            persona.name = name; persona.emoji = emoji; persona.tagline = tagline
            persona.backstory = backstory; persona.speakingStyle = speakingStyle
            persona.language = language; persona.exampleChats = exampleChats
        } else {
            context.insert(Persona(name: name, emoji: emoji, tagline: tagline,
                                   backstory: backstory, speakingStyle: speakingStyle,
                                   exampleChats: exampleChats, language: language))
        }
        try? context.save()
        dismiss()
    }
}
