//
//  AkariApp.swift
//  Akari
//

import SwiftUI
import SwiftData

@main
struct AkariApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Persona.self, Conversation.self, Message.self, MemoryFact.self])
    }
}
