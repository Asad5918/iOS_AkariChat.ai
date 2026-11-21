import SwiftUI
import Combine
import PhotosUI
import UIKit

// MARK: - Data

struct FeedComment: Identifiable {
    let id = UUID()
    let author: String
    let text: String
}

struct FeedPost: Identifiable {
    let id = UUID()
    let author: String
    let emoji: String
    let colors: [Color]
    let time: String
    let text: String
    var image: UIImage? = nil
    var banner: [Color]? = nil
    var bannerEmoji: String? = nil
    var likes: Int
    var liked = false
    var comments: [FeedComment]
}

@Observable
final class FeedStore {
    var posts: [FeedPost] = FeedStore.demo

    func index(of id: UUID) -> Int? { posts.firstIndex { $0.id == id } }

    func toggleLike(_ id: UUID) {
        guard let i = index(of: id) else { return }
        posts[i].liked.toggle()
        posts[i].likes += posts[i].liked ? 1 : -1
    }

    func addComment(_ text: String, to id: UUID) {
        guard let i = index(of: id) else { return }
        posts[i].comments.append(FeedComment(author: "You", text: text))
    }

    @discardableResult
    func addPost(_ text: String, image: UIImage? = nil) -> UUID {
        let post = FeedPost(author: "You", emoji: "😎", colors: [.indigo, .purple], time: "now",
                            text: text, image: image, likes: 0, comments: [])
        posts.insert(post, at: 0)
        return post.id
    }

    static let demo: [FeedPost] = [
        FeedPost(author: "Maya", emoji: "🌿", colors: [.green, .teal], time: "2m",
                 text: "finally finished the logo i've been procrastinating on for a week lol. coffee was the real mvp ☕",
                 banner: [.green, .mint], bannerEmoji: "🎨", likes: 42,
                 comments: [FeedComment(author: "Leo", text: "show us!!"), FeedComment(author: "Riya", text: "proud of you yaar 😭")]),
        FeedPost(author: "Riya", emoji: "🌸", colors: [.pink, .orange], time: "9m",
                 text: "arre kal ka plan kya hai? koi chai pe chal raha hai kya? ☕🌸", likes: 28,
                 comments: [FeedComment(author: "Aarav", text: "bhai main aa raha hu, biryani bhi le aana")]),
        FeedPost(author: "Leo", emoji: "🎧", colors: [.blue, .indigo], time: "17m",
                 text: "new PR on deadlifts today. legs are gone, can't walk haha",
                 banner: [.blue, .cyan], bannerEmoji: "🏋️", likes: 64,
                 comments: [FeedComment(author: "Maya", text: "beast mode"), FeedComment(author: "Zoe", text: "rest day tomorrow!!")]),
        FeedPost(author: "Zoe", emoji: "📷", colors: [.purple, .pink], time: "31m",
                 text: "golden hour at the pier today was unreal. some moments you just can't edit.",
                 banner: [.orange, .pink], bannerEmoji: "🌅", likes: 117,
                 comments: [FeedComment(author: "Kabir", text: "need that wallpaper")]),
        FeedPost(author: "Aarav", emoji: "🏏", colors: [.orange, .red], time: "45m",
                 text: "bhai aaj ka match kya tha!! last over mein jeet gaye, dil ki dhadkan band ho gayi 😂", likes: 53,
                 comments: [FeedComment(author: "Riya", text: "haha tu toh chilla raha tha")]),
        FeedPost(author: "Dr. Ellis", emoji: "📚", colors: [.brown, .yellow], time: "1h",
                 text: "A small thought for today: curiosity is a muscle. Ask one better question than yesterday.", likes: 89,
                 comments: [FeedComment(author: "Kabir", text: "Saving this one.")]),
        FeedPost(author: "Kabir", emoji: "🎸", colors: [.mint, .blue], time: "2h",
                 text: "weekend trek planned! anyone up for a sunrise hike? bringing the guitar, badly played songs guaranteed 🎶",
                 banner: [.teal, .blue], bannerEmoji: "⛰️", likes: 71,
                 comments: [FeedComment(author: "Zoe", text: "i'm in, will bring camera"), FeedComment(author: "Aarav", text: "bhai guitar mat laana 😂")]),
        FeedPost(author: "Maya", emoji: "🌿", colors: [.green, .teal], time: "3h",
                 text: "biscuit knocked my plant off the shelf again. we are not on speaking terms.", likes: 96,
                 comments: [FeedComment(author: "Leo", text: "classic cat behaviour")]),
    ]
}

// MARK: - Home

struct HomeView: View {
    @State private var store = FeedStore()
    @State private var position: UUID?
    @State private var autoScroll = true
    @State private var pausedUntil = Date.distantPast
    @State private var composing = false
    @State private var commentingOn: UUID?

    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                composerBar
                ScrollView {
                    LazyVStack(spacing: 14) {
                        ForEach(store.posts) { post in
                            PostCard(
                                post: post,
                                onLike: { pause(); Haptics.soft(); store.toggleLike(post.id) },
                                onComment: { pause(); commentingOn = post.id }
                            )
                            .id(post.id)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .scrollPosition(id: $position, anchor: .top)
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in pause() })
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { liveBadge }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        autoScroll.toggle()
                    } label: {
                        Image(systemName: autoScroll ? "pause.circle.fill" : "play.circle.fill")
                    }
                    .accessibilityLabel(autoScroll ? "Pause auto-scroll" : "Resume auto-scroll")
                }
            }
            .onReceive(timer) { _ in advance() }
            .sheet(isPresented: $composing) {
                ComposeSheet { text, image in
                    let id = store.addPost(text, image: image)
                    withAnimation { position = id }
                }
            }
            .sheet(isPresented: Binding(get: { commentingOn != nil }, set: { if !$0 { commentingOn = nil } })) {
                if let id = commentingOn {
                    CommentsSheet(store: store, postID: id)
                }
            }
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 5) {
            Circle().fill(.red).frame(width: 7, height: 7)
            Text("LIVE").font(.caption.weight(.bold)).foregroundStyle(.red)
                .fixedSize()
        }
        .fixedSize()
    }

    private var composerBar: some View {
        Button { pause(); composing = true } label: {
            HStack(spacing: 10) {
                Text("😎").font(.title2)
                Text("What's on your mind?")
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: "square.and.pencil").foregroundStyle(.tint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.background, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func pause() {
        pausedUntil = Date().addingTimeInterval(8)
    }

    /// Slowly moves through the feed (and loops) unless the user is interacting.
    private func advance() {
        guard autoScroll, !composing, commentingOn == nil, Date() > pausedUntil, !store.posts.isEmpty else { return }
        let current = position.flatMap { id in store.posts.firstIndex { $0.id == id } } ?? -1
        let next = current + 1 < store.posts.count ? store.posts[current + 1].id : store.posts[0].id
        withAnimation(.easeInOut(duration: 1.2)) { position = next }
    }
}

// MARK: - Post card

struct PostCard: View {
    let post: FeedPost
    let onLike: () -> Void
    let onComment: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text(post.emoji)
                    .font(.title2)
                    .frame(width: 42, height: 42)
                    .background(LinearGradient(colors: post.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(post.author).font(.subheadline.weight(.semibold))
                    Text(post.time).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            if !post.text.isEmpty { Text(post.text).font(.body) }

            if let image = post.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else if let banner = post.banner {
                ZStack {
                    LinearGradient(colors: banner, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(post.bannerEmoji ?? "").font(.system(size: 64))
                }
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            HStack(spacing: 22) {
                Button(action: onLike) {
                    Label("\(post.likes)", systemImage: post.liked ? "heart.fill" : "heart")
                        .foregroundStyle(post.liked ? .pink : .secondary)
                        .symbolEffect(.bounce, value: post.liked)
                }
                Button(action: onComment) {
                    Label("\(post.comments.count)", systemImage: "bubble.left")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .font(.subheadline.weight(.medium))
            .buttonStyle(PressableStyle())

            if let last = post.comments.last {
                Button(action: onComment) {
                    (Text(last.author + "  ").bold() + Text(last.text))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Sheets

struct ComposeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var image: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @FocusState private var focused: Bool
    let onPost: (String, UIImage?) -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $text)
                    .focused($focused)
                    .frame(minHeight: 90)

                if let image {
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(maxWidth: .infinity)
                            .frame(height: 170)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Button { self.image = nil; pickerItem = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.6))
                                .padding(8)
                        }
                        .accessibilityLabel("Remove photo")
                    }
                }

                HStack(spacing: 20) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("Gallery", systemImage: "photo.on.rectangle")
                    }
                    if cameraAvailable {
                        Button { focused = false; showingCamera = true } label: {
                            Label("Camera", systemImage: "camera")
                        }
                    }
                    Spacer()
                }
                .font(.subheadline.weight(.medium))
                .glassButtons()
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onPost(trimmed, image)
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty && image == nil)
                }
            }
            .onAppear { focused = true }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let picked = UIImage(data: data) {
                        image = picked
                    }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image = $0 }.ignoresSafeArea()
            }
        }
        .presentationDetents([.medium, .large])
    }
}

extension View {
    /// Liquid Glass button style on iOS 26+, plain bordered buttons before that.
    @ViewBuilder func glassButtons() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

/// Wraps the system camera (UIImagePickerController).
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

struct CommentsSheet: View {
    let store: FeedStore
    let postID: UUID
    @State private var draft = ""

    private var comments: [FeedComment] {
        store.index(of: postID).map { store.posts[$0].comments } ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if comments.isEmpty {
                    ContentUnavailableView("No comments yet", systemImage: "bubble.left", description: Text("Be the first to say something."))
                } else {
                    List(comments) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.author).font(.subheadline.weight(.semibold))
                            Text(c.text).font(.body)
                        }
                    }
                    .listStyle(.plain)
                }
                HStack(spacing: 8) {
                    TextField("Add a comment…", text: $draft)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color(.secondarySystemBackground), in: Capsule())
                    Button {
                        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !text.isEmpty else { return }
                        store.addComment(text, to: postID)
                        draft = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill").font(.system(size: 32))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    HomeView()
}
