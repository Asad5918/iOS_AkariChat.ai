import SwiftUI

/// Wraps chips onto multiple lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// Expanded profile: photo carousel, about, interests and like / pass buttons.
struct ProfileDetailView: View {
    let profile: DemoProfile
    var distanceKm: Double?
    let onNope: () -> Void
    let onLike: () -> Void

    @State private var page = 0

    /// Demo "photos": the profile's gradient with a different emoji per page.
    private var photos: [(emoji: String, colors: [Color])] {
        let emojis = [profile.emoji] + profile.interests.compactMap { $0.first.map(String.init) }.prefix(2)
        return emojis.enumerated().map { i, e in
            (e, i % 2 == 0 ? profile.colors : profile.colors.reversed())
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                carousel
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(profile.name).font(.system(size: 32, weight: .bold))
                            Text("\(profile.age)").font(.system(size: 26))
                        }
                        Text(profile.gender.title).font(.subheadline).foregroundStyle(.secondary)
                        Label(distanceKm.map { "\(profile.city) · \(Int($0.rounded())) km away" } ?? profile.city,
                              systemImage: "mappin.and.ellipse")
                            .font(.subheadline)
                    }
                    section("About") { Text(profile.bio).font(.body) }
                    section("Interests") {
                        FlowLayout(spacing: 8) {
                            ForEach(profile.interests, id: \.self) { interest in
                                Text(interest)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 110)
        }
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { actions }
        .presentationDragIndicator(.visible)
    }

    private var carousel: some View {
        TabView(selection: $page) {
            ForEach(Array(photos.enumerated()), id: \.offset) { i, photo in
                ZStack {
                    LinearGradient(colors: photo.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(photo.emoji).font(.system(size: 140))
                }
                .tag(i)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .frame(height: 440)
        .onChange(of: page) { Haptics.select() }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private var actions: some View {
        HStack(spacing: 36) {
            circle("xmark", .red, Haptics.tap, onNope)
            circle("heart.fill", .green, Haptics.tap, onLike)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func circle(_ symbol: String, _ color: Color, _ haptic: @escaping () -> Void, _ action: @escaping () -> Void) -> some View {
        Button {
            haptic()
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
    }
}

/// "It's a match!" celebration with rising hearts and two avatars sliding together.
struct MatchView: View {
    let profile: DemoProfile
    let onMessage: () -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var rise = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.45, green: 0.2, blue: 0.85)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            hearts

            VStack(spacing: 28) {
                Spacer()
                Text("It's a match!")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .scaleEffect(appeared ? 1 : 0.3)
                    .opacity(appeared ? 1 : 0)
                Text("You and \(profile.name) liked each other")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(appeared ? 1 : 0)

                HStack(spacing: -22) {
                    Group {
                        if UserProfileStore.shared.profile.hasPhoto {
                            UserAvatar(size: 150)
                                .overlay(Circle().stroke(.white, lineWidth: 5))
                                .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
                        } else {
                            avatar(UserProfileStore.shared.profile.emoji, [.indigo, .purple])
                        }
                    }
                        .offset(x: appeared ? 0 : -220)
                        .rotationEffect(.degrees(appeared ? -8 : -30))
                    avatar(profile.emoji, profile.colors)
                        .offset(x: appeared ? 0 : 220)
                        .rotationEffect(.degrees(appeared ? 8 : 30))
                }
                .padding(.vertical, 12)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        Haptics.tap()
                        onMessage()
                    } label: {
                        Text("Send a message")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.white, in: Capsule())
                            .foregroundStyle(Color(red: 0.8, green: 0.15, blue: 0.45))
                    }
                    Button("Keep swiping") { onDismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.vertical, 8)
                }
                .buttonStyle(PressableStyle())
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.6)) { appeared = true }
            withAnimation(.easeOut(duration: 2.4)) { rise = true }
        }
    }

    private func avatar(_ emoji: String, _ colors: [Color]) -> some View {
        Text(emoji)
            .font(.system(size: 74))
            .frame(width: 150, height: 150)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 5))
            .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }

    /// A burst of hearts drifting upward.
    private var hearts: some View {
        GeometryReader { geo in
            ForEach(0..<16, id: \.self) { i in
                let x = CGFloat((i * 53) % 100) / 100 * geo.size.width
                Text(i % 3 == 0 ? "💖" : "❤️")
                    .font(.system(size: CGFloat(18 + (i * 7) % 22)))
                    .position(x: x, y: geo.size.height + 30)
                    .offset(y: rise ? -(geo.size.height * (0.55 + CGFloat(i % 5) * 0.12)) : 0)
                    .opacity(rise ? 0 : 0.9)
                    .animation(.easeOut(duration: 2.4).delay(Double(i) * 0.08), value: rise)
            }
        }
        .allowsHitTesting(false)
    }
}
