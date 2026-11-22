import SwiftUI
import PhotosUI

/// Your avatar: photo if set, otherwise your emoji on a gradient.
struct UserAvatar: View {
    var size: CGFloat = 42
    private var store: UserProfileStore { .shared }

    var body: some View {
        Group {
            if let photo = store.photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                Text(store.profile.emoji)
                    .font(.system(size: size * 0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LinearGradient(colors: [.indigo, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}

/// The "You" tab: your profile, which personas use to get to know you.
struct ProfileView: View {
    @State private var editing = false
    @State private var showingSettings = false
    private var store: UserProfileStore { .shared }

    var body: some View {
        let p = store.profile
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 10) {
                        UserAvatar(size: 110)
                            .overlay(Circle().stroke(.background, lineWidth: 4))
                            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                        Text(p.name.isEmpty ? "Add your name" : p.name)
                            .font(.title.bold())
                            .foregroundStyle(p.name.isEmpty ? .secondary : .primary)
                        let subtitle = [p.age.map(String.init), p.gender == .unspecified ? nil : p.gender.title, p.city.isEmpty ? nil : p.city]
                            .compactMap { $0 }.joined(separator: " · ")
                        if !subtitle.isEmpty {
                            Text(subtitle).foregroundStyle(.secondary)
                        }
                        Button { editing = true } label: {
                            Label("Edit profile", systemImage: "pencil")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section("About") {
                    Text(p.bio.isEmpty ? "Tell personas a little about yourself." : p.bio)
                        .foregroundStyle(p.bio.isEmpty ? .secondary : .primary)
                }

                Section("Interests") {
                    if p.interests.isEmpty {
                        Text("No interests yet.").foregroundStyle(.secondary)
                    } else {
                        FlowLayout(spacing: 8) {
                            ForEach(p.interests, id: \.self) { interest in
                                Text(interest)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(.tertiarySystemFill), in: Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section {
                    Button { showingSettings = true } label: {
                        Label("Model & generation settings", systemImage: "cpu")
                    }
                } footer: {
                    Text("Your profile stays on this phone. Personas use it to know your name and what you're into.")
                }
            }
            .navigationTitle("You")
            .sheet(isPresented: $editing) { ProfileEditor() }
            .sheet(isPresented: $showingSettings) { SettingsView() }
        }
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = UserProfileStore.shared.profile
    @State private var ageText = UserProfileStore.shared.profile.age.map(String.init) ?? ""
    @State private var interestsText = UserProfileStore.shared.profile.interests.joined(separator: ", ")
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    private var store: UserProfileStore { .shared }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        UserAvatar(size: 72)
                        VStack(alignment: .leading, spacing: 8) {
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label("Choose photo", systemImage: "photo.on.rectangle")
                            }
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                            }
                            if store.profile.hasPhoto {
                                Button("Remove photo", role: .destructive) { store.setPhoto(nil) }
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    TextField("Emoji (shown without a photo)", text: $draft.emoji)
                }
                Section("Basics") {
                    TextField("Name", text: $draft.name)
                        .textContentType(.givenName)
                    TextField("Age", text: $ageText)
                        .keyboardType(.numberPad)
                    Picker("Gender", selection: $draft.gender) {
                        ForEach(UserProfile.Gender.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("City", text: $draft.city)
                }
                Section("About you") {
                    TextEditor(text: $draft.bio).frame(minHeight: 100)
                }
                Section {
                    TextField("e.g. music, cricket, coffee", text: $interestsText)
                } header: {
                    Text("Interests")
                } footer: {
                    Text("Separate with commas.")
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).bold() }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        store.setPhoto(image)
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { store.setPhoto($0) }.ignoresSafeArea()
            }
        }
    }

    private func save() {
        var p = draft
        p.name = p.name.trimmingCharacters(in: .whitespaces)
        p.city = p.city.trimmingCharacters(in: .whitespaces)
        p.bio = p.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        p.emoji = p.emoji.trimmingCharacters(in: .whitespaces).isEmpty ? "😎" : String(p.emoji.trimmingCharacters(in: .whitespaces).prefix(2))
        p.age = Int(ageText.trimmingCharacters(in: .whitespaces)).flatMap { (13...120).contains($0) ? $0 : nil }
        p.interests = interestsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        p.hasPhoto = store.profile.hasPhoto
        store.profile = p
        Haptics.success()
        dismiss()
    }
}
