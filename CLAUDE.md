# Akari

iOS app (SwiftUI, iOS 17+) where you chat and talk with human-sounding AI personas that run **fully on-device** via MLX Swift. Tabs: Home (static social feed), Discover (swipe deck, demo data), Chats (personas + chat + voice call), You (your profile).

## Build & run

- Project: `Akari.xcodeproj`, scheme `Akari`, bundle ID `com.akari.Akarichat`. Sources are in `Akari/` (a file-system synchronized group: new files are picked up automatically, no pbxproj edits needed).
- Build for simulator:
  ```bash
  xcodebuild -project Akari.xcodeproj -scheme Akari -destination 'generic/platform=iOS Simulator' -skipMacroValidation -skipPackagePluginValidation build
  ```
  `-skipMacroValidation` is required (MLXHuggingFace macros). Don't use `name=iPhone 15`-style destinations.
- Needs the Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`).
- **MLX cannot run in the Simulator.** There, `ModelManager` falls back to `MockEngine` (canned replies). Real inference, model switching and voice-call quality must be tested on a physical iPhone (the app uses the increased-memory-limit entitlement in `Akari.entitlements`).
- Simulator used so far: iPhone 17, UDID `37CFB7AF-4920-43F2-A2C8-822B7B7EE485`. Always pass the device explicitly; don't touch other simulators.

## Architecture (`Akari/`)

- `Engine/`: `LLMEngine` protocol (`stream(turns:params:)`), `MLXEngine` (real), `MockEngine` (simulator), `ModelManager` (`@Observable`; model list, download/load/switch, UserDefaults keys `selectedModelID` / `downloadedModelIDs`). Unloads the current model before loading another. Gemma 2 has no system role, so the system prompt is folded into the first user turn.
- `Models/Models.swift`: SwiftData models `Persona` (incl. `language`, `exampleChats`), `Conversation`, `Message`, `MemoryFact`. New properties must have defaults so existing stores migrate.
- `Services/`: `PromptBuilder` (system prompt, Hinglish block, example chats, voice-call mode, history char budget), `ReplyFormatter` (strips markdown/assistant-isms, splits into bubbles, typing delay, `spoken()` for TTS).
- `Models/ChatGame.swift`: games/role-plays (Truth or Dare, 20 Questions, Would You Rather, First Date, Job Interview). The active game and its app-chosen secret/role live on `Conversation` (`gameRaw`, `gameSeed`) and are injected into the system prompt by `PromptBuilder`; a hidden start cue (not saved) makes the persona open the game.
- `Features/Chat`: chat UI + `ChatViewModel`. `Features/Personas`: list, editor, first-launch model setup, `SettingsView` (model switcher, custom HF repo, sampling sliders). `Features/Call`: `VoiceCallManager` + `CallView` (on-device speech recognition → LLM → `AVSpeechSynthesizer`). `Features/Discover` and `Features/Home`: UI with static demo data only. Discover has filters (`DiscoverFilter.swift`: age range, gender, MapKit pin + radius, optional "Use my location" via CoreLocation; `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription`). `DemoProfile` carries `gender`/`latitude`/`longitude`.
- `ContentView` shows `ModelSetupView` until a model has loaded once, then the tab bar.

- Chat extras: `Message` has `reaction`, `seen`, `imageData` (all optional/defaulted). Read receipts and "typing…" come from `ChatViewModel` (`awaitingRead`, `showTyping`); "online / last seen" from `Presence` in `Services/Polish.swift`, which also holds `Haptics` and `PressableStyle`. Photos in chat are noted in the prompt as "[user sent a photo]" (the model can't see them). `AppRouter` lets Discover open a chat in the Chats tab after a match; Discover has `ProfileDetailView` and `MatchView` in `DiscoverDetail.swift`.

- "You" tab: `Features/Profile/ProfileView.swift` (profile + `ProfileEditor`, `UserAvatar`). `Services/UserProfile.swift` holds `UserProfile` (name, emoji, age, gender, city, bio, interests) and `UserProfileStore.shared` (JSON in UserDefaults key `userProfile`, photo at Documents/profile.jpg). `UserProfile.promptLine` is added to the system prompt right after the rules (keep the text identical to the Android port); Home posts/comments and the match screen use your name and avatar.

## Conventions & gotchas

- Project uses `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (Swift 5 mode). Code that runs on audio/speech threads (tap blocks, recognition callbacks, delegate methods) must be `nonisolated`.
- "Human" feel comes from: persona prompt + example chats, sampling (temp 0.85, top-p 0.9, repetition 1.1, max 160 tokens), reply formatting, and typing delays. Tune examples and sampling before changing models.
- Hinglish personas reply in Roman-script Hinglish; call speech recognition uses `hi-IN`, TTS uses `en-IN`.
- Info.plist is generated from build settings (`INFOPLIST_KEY_*` in the pbxproj), including the microphone and speech-recognition usage strings. If you hand-edit the pbxproj, use tabs and 24-character hex IDs.
- Git: work on `main`. This repo belongs to a separate GitHub account from the user's other projects, so commits use the repo-local `user.name` / `user.email` (check `git config user.email` before committing), and the remote uses an SSH host alias or GitHub Desktop for that account.

## Not built yet

Memory extraction/summarizer and memory viewer (plan Phase 4), persistence for Home/Discover data, real user-to-user calls (needs a backend), monetization.
