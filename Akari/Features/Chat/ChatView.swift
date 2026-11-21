import SwiftUI
import SwiftData
import Combine
import PhotosUI

struct ChatView: View {
    @State private var viewModel: ChatViewModel
    @State private var draft = ""
    @FocusState private var focused: Bool

    @Environment(ModelManager.self) private var manager
    @State private var showingSettings = false
    @State private var showingCall = false

    // Photo attachment
    @State private var pendingImage: UIImage?
    @State private var showAttachChoices = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var sendTick = 0

    private let conversation: Conversation
    private let context: ModelContext

    init(conversation: Conversation, manager: ModelManager, context: ModelContext) {
        self.conversation = conversation
        self.context = context
        _viewModel = State(initialValue: ChatViewModel(
            conversation: conversation, engineProvider: { manager.engine }, context: context))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let game = conversation.game {
                gameBanner(game)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(conversation.sortedMessages) { message in
                            BubbleView(message: message,
                                       receipt: receipt(for: message),
                                       onReact: { viewModel.react(to: message, with: $0) })
                                .id(message.id)
                                .transition(.scale(scale: 0.85, anchor: message.role == .user ? .bottomTrailing : .bottomLeading)
                                    .combined(with: .opacity))
                        }
                        if viewModel.showTyping {
                            TypingIndicator().id("typing")
                                .transition(.scale(scale: 0.85, anchor: .bottomLeading).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: conversation.messages.count)
                    .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.showTyping)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: conversation.messages.count) { scrollToEnd(proxy) }
                .onChange(of: viewModel.showTyping) { scrollToEnd(proxy) }
                .onAppear { scrollToEnd(proxy, animated: false) }
            }

            if let error = viewModel.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red).padding(.horizontal)
            }
            if let pendingImage {
                attachmentPreview(pendingImage)
            }
            inputBar
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(conversation.persona?.name ?? "Chat").font(.headline)
                    Text(statusLine)
                        .font(.caption2)
                        .foregroundStyle(statusIsOnline ? Color.green : Color.secondary)
                        .contentTransition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: statusLine)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingCall = true } label: { Image(systemName: "phone.fill") }
                    .accessibilityLabel("Voice call")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSettings = true } label: { Image(systemName: "cpu") }
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .fullScreenCover(isPresented: $showingCall) {
            CallView(conversation: conversation, manager: manager, context: context)
        }
        .confirmationDialog("Add a photo", isPresented: $showAttachChoices) {
            Button("Photo Library") { showLibrary = true }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Camera") { showCamera = true }
            }
        }
        .photosPicker(isPresented: $showLibrary, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { pendingImage = $0 }.ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pendingImage = image }
                }
                pickerItem = nil
            }
        }
    }

    // MARK: - Status

    private var statusIsOnline: Bool {
        viewModel.showTyping || (!isModelBusy && Presence.isOnline(since: lastActive))
    }

    /// A chat with no messages yet counts as active now.
    private var lastActive: Date { conversation.messages.isEmpty ? Date() : conversation.updatedAt }

    private var isModelBusy: Bool {
        switch manager.state {
        case .downloading, .loading: true
        default: false
        }
    }

    /// "typing…", model progress, "online" or "last seen 3 hours ago".
    private var statusLine: String {
        if viewModel.showTyping { return "typing…" }
        switch manager.state {
        case .downloading(let f): return "downloading \(Int(f * 100))%…"
        case .loading: return "loading model…"
        default: return Presence.text(since: lastActive)
        }
    }

    /// "Seen" / "Delivered" under the newest message you sent.
    private func receipt(for message: Message) -> String? {
        guard message.role == .user,
              message.id == conversation.sortedMessages.last(where: { $0.role == .user })?.id else { return nil }
        // Messages from before read receipts existed count as seen once anything came after them.
        let answered = conversation.sortedMessages.contains { $0.role == .assistant && $0.createdAt > message.createdAt }
        return message.seen || answered ? "Seen" : "Delivered"
    }

    // MARK: - Pieces

    private func gameBanner(_ game: ChatGame) -> some View {
        HStack(spacing: 8) {
            Text("\(game.emoji) \(game.title)").font(.footnote.weight(.semibold))
            Spacer()
            Button("End") { viewModel.endGame() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var gameMenu: some View {
        Menu {
            Section("Games") {
                ForEach(ChatGame.allCases.filter { !$0.isRolePlay }) { game in
                    Button("\(game.emoji) \(game.title)") { viewModel.startGame(game) }
                }
            }
            Section("Role-play") {
                ForEach(ChatGame.allCases.filter(\.isRolePlay)) { game in
                    Button("\(game.emoji) \(game.title)") { viewModel.startGame(game) }
                }
            }
            if conversation.game != nil {
                Section {
                    Button("End game", role: .destructive) { viewModel.endGame() }
                }
            }
        } label: {
            Image(systemName: "gamecontroller.fill").font(.system(size: 26))
        }
        .disabled(viewModel.isTyping)
        .accessibilityLabel("Games")
    }

    private func attachmentPreview(_ image: UIImage) -> some View {
        HStack {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pendingImage = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                        .font(.title3)
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("Remove photo")
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(.bar)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pendingImage != nil
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            gameMenu
                .frame(height: 36)
            Button { focused = false; showAttachChoices = true } label: {
                Image(systemName: "photo.badge.plus").font(.system(size: 24))
            }
            .buttonStyle(PressableStyle())
            .frame(height: 36)
            .disabled(viewModel.isTyping)
            .accessibilityLabel("Add photo")
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            Button {
                let text = draft
                let image = pendingImage
                draft = ""
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { pendingImage = nil }
                sendTick += 1
                viewModel.send(text, image: image)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    .symbolEffect(.bounce, value: sendTick)
            }
            .buttonStyle(PressableStyle())
            .disabled(!canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        let id: AnyHashable? = viewModel.showTyping ? "typing" : conversation.sortedMessages.last?.id
        guard let id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .bottom) }
        } else {
            proxy.scrollTo(id, anchor: .bottom)
        }
    }
}

struct BubbleView: View {
    let message: Message
    var receipt: String? = nil
    var onReact: (String) -> Void = { _ in }

    private var isUser: Bool { message.role == .user }
    private static let reactions: [(emoji: String, name: String)] = [
        ("❤️", "Love"), ("😂", "Haha"), ("👍", "Like"), ("😮", "Wow"), ("😢", "Sad"), ("🙏", "Thanks"),
    ]

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 2) {
            HStack {
                if isUser { Spacer(minLength: 48) }
                content
                    .overlay(alignment: isUser ? .bottomLeading : .bottomTrailing) {
                        if let reaction = message.reaction {
                            Text(reaction)
                                .font(.footnote)
                                .padding(4)
                                .background(.regularMaterial, in: Circle())
                                .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                                .offset(x: isUser ? -6 : 6, y: 14)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.3, dampingFraction: 0.5), value: message.reaction)
                    .contextMenu {
                        ForEach(Self.reactions, id: \.emoji) { item in
                            Button { onReact(item.emoji) } label: {
                                if message.reaction == item.emoji {
                                    Label("\(item.emoji) \(item.name)", systemImage: "checkmark")
                                } else {
                                    Text("\(item.emoji) \(item.name)")
                                }
                            }
                        }
                        if !message.text.isEmpty {
                            Button { UIPasteboard.general.string = message.text } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                            }
                        }
                    }
                if !isUser { Spacer(minLength: 48) }
            }
            if let receipt {
                Text(receipt)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.25), value: receipt)
            }
        }
        .padding(.bottom, message.reaction == nil ? 0 : 12)
    }

    @ViewBuilder private var content: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
            if let data = message.imageData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if !message.text.isEmpty {
                Text(message.text)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .foregroundStyle(isUser ? Color.white : Color.primary)
                    .background(isUser ? Color.accentColor : Color(.systemGray5),
                                in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

struct TypingIndicator: View {
    @State private var phase = 0
    private let timer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()

    var body: some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 7, height: 7)
                        .opacity(phase == i ? 1 : 0.35)
                        .scaleEffect(phase == i ? 1.15 : 0.9)
                        .animation(.easeInOut(duration: 0.3), value: phase)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer()
        }
        .onReceive(timer) { _ in phase = (phase + 1) % 3 }
    }
}
