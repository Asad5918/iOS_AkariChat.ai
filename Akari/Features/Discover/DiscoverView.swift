import SwiftUI
import UIKit
import CoreLocation
import SwiftData

/// Demo profile shown in the swipe deck. Gradient + emoji stand in for photos until real images are added.
struct DemoProfile: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let age: Int
    let city: String
    let gender: Gender
    let latitude: Double
    let longitude: Double
    let bio: String
    let emoji: String
    let colors: [Color]
    var interests: [String] = []

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    static let all: [DemoProfile] = [
        .init(name: "Maya", age: 24, city: "Brooklyn", gender: .woman, latitude: 40.6782, longitude: -73.9442, bio: "Graphic designer. Cat mom to Biscuit. Will judge your playlist.", emoji: "🌿", colors: [.green, .teal], interests: ["🎨 Design", "🐱 Cats", "🎵 Indie music", "☕ Coffee"]),
        .init(name: "Riya", age: 23, city: "Delhi", gender: .woman, latitude: 28.6139, longitude: 77.209, bio: "Chai first, everything else later. Bollywood quotes on demand.", emoji: "🌸", colors: [.pink, .orange], interests: ["☕ Chai", "🎬 Bollywood", "🍜 Street food", "💃 Dancing"]),
        .init(name: "Leo", age: 27, city: "Austin", gender: .man, latitude: 30.2672, longitude: -97.7431, bio: "Physio by day, leg-day enthusiast by choice. I cook, you pick the movie.", emoji: "🎧", colors: [.blue, .indigo], interests: ["🏋️ Lifting", "🍳 Cooking", "🎧 Music", "🎬 Movies"]),
        .init(name: "Aarav", age: 26, city: "Mumbai", gender: .man, latitude: 19.076, longitude: 72.8777, bio: "Cricket, gaming, biryani. Will roast you lovingly.", emoji: "🏏", colors: [.orange, .red], interests: ["🏏 Cricket", "🎮 Gaming", "🍛 Biryani", "😂 Memes"]),
        .init(name: "Dr. Ellis", age: 50, city: "Edinburgh", gender: .man, latitude: 55.9533, longitude: -3.1883, bio: "Retired professor. Ask me anything, I'll ask a better question back.", emoji: "📚", colors: [.brown, .yellow], interests: ["📚 Books", "♟️ Chess", "🥾 Hiking", "🍷 Wine tasting"]),
        .init(name: "Zoe", age: 25, city: "London", gender: .nonBinary, latitude: 51.5072, longitude: -0.1276, bio: "Photographer chasing golden hour. Always up for a street food crawl.", emoji: "📷", colors: [.purple, .pink], interests: ["📷 Photography", "🌅 Golden hour", "🍢 Street food", "✈️ Travel"]),
        .init(name: "Kabir", age: 28, city: "Bengaluru", gender: .man, latitude: 12.9716, longitude: 77.5946, bio: "Startup guy who also plays guitar badly. Weekend treks are my therapy.", emoji: "🎸", colors: [.mint, .blue], interests: ["🎸 Guitar", "🥾 Trekking", "🚀 Startups", "☕ Filter coffee"]),
    ]
}

struct DiscoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppRouter.self) private var router
    @Query private var personas: [Persona]
    @State private var deck = DemoProfile.all
    @State private var liked: [DemoProfile] = []
    @State private var drag: CGSize = .zero
    @State private var isAnimatingOut = false
    @State private var filter = DiscoverFilter()
    @State private var swiped: Set<UUID> = []
    @State private var showingFilters = false
    @State private var detail: DemoProfile?
    @State private var matched: DemoProfile?

    private let threshold: CGFloat = 110

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ZStack {
                    if deck.isEmpty {
                        emptyState
                    }
                    ForEach(Array(deck.prefix(3).enumerated()).reversed(), id: \.element.id) { index, profile in
                        ProfileCard(profile: profile, dragX: index == 0 ? drag.width : 0, distanceKm: filter.distanceKm(to: profile))
                            .scaleEffect(index == 0 ? 1 : 1 - 0.05 * CGFloat(index))
                            .offset(y: index == 0 ? 0 : CGFloat(index) * 14)
                            .offset(index == 0 ? drag : .zero)
                            .rotationEffect(.degrees(index == 0 ? Double(drag.width / 18) : 0))
                            .allowsHitTesting(index == 0)
                            .gesture(index == 0 ? dragGesture : nil)
                            .onTapGesture {
                                guard index == 0, !isAnimatingOut else { return }
                                Haptics.select()
                                detail = profile
                            }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                actionButtons
                    .padding(.bottom, 12)
            }
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $detail) { profile in
                ProfileDetailView(
                    profile: profile,
                    distanceKm: filter.distanceKm(to: profile),
                    onNope: { detail = nil; decide(like: false) },
                    onLike: { detail = nil; decide(like: true) })
            }
            .fullScreenCover(item: $matched) { profile in
                MatchView(profile: profile,
                          onMessage: { openChat(with: profile) },
                          onDismiss: { matched = nil })
            }
            .sheet(isPresented: $showingFilters) {
                DiscoverFilterSheet(filter: filter) { applyFilter($0) }
                    .presentationDetents([.large])
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingFilters = true } label: {
                        Image(systemName: filter.isActive
                              ? "line.3.horizontal.decrease.circle.fill"
                              : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filters")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                        Text("\(liked.count)")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
                }
            }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard !isAnimatingOut else { return }
                drag = value.translation
            }
            .onEnded { value in
                guard !isAnimatingOut else { return }
                if value.translation.width > threshold {
                    swipe(like: true)
                } else if value.translation.width < -threshold {
                    swipe(like: false)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private var actionButtons: some View {
        HStack(spacing: 36) {
            circleButton("xmark", color: .red) { swipe(like: false) }
            circleButton("heart.fill", color: .green) { swipe(like: true) }
        }
        .opacity(deck.isEmpty ? 0.3 : 1)
        .disabled(deck.isEmpty)
    }

    private func circleButton(_ symbol: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 64, height: 64)
                .background(.background, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        }
        .buttonStyle(PressableStyle())
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("🎉").font(.system(size: 56))
            Text(filter.isActive ? "No one matches" : "You're all caught up").font(.title3.weight(.semibold))
            Text(filter.isActive ? "Try widening your filters." : "Check back later for new people.")
                .foregroundStyle(.secondary)
            if filter.isActive {
                Button("Clear filters") { applyFilter(DiscoverFilter()) }
                    .buttonStyle(.bordered)
            }
            Button("Start over") {
                swiped = []
                liked = []
                deck = DemoProfile.all.filter(filter.matches)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    /// Swipes after a sheet has finished dismissing.
    private func decide(like: Bool) {
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            swipe(like: like)
        }
    }

    /// Creates the persona for a match if needed and opens its chat in the Chats tab.
    private func openChat(with profile: DemoProfile) {
        let persona: Persona
        if let existing = personas.first(where: { $0.name == profile.name }) {
            persona = existing
        } else {
            let hinglish = ["Delhi", "Mumbai", "Bengaluru"].contains(profile.city)
            persona = Persona(
                name: profile.name, emoji: profile.emoji, tagline: profile.bio,
                backstory: "You're \(profile.name), \(profile.age), from \(profile.city). \(profile.bio) Your interests: \(profile.interests.joined(separator: ", ")). You and the user just matched on a dating app, so you're friendly, a little playful and curious about them. Keep it respectful and PG.",
                speakingStyle: "casual, short texts, mostly lowercase, light emoji.",
                language: hinglish ? .hinglish : .english)
            context.insert(persona)
            try? context.save()
        }
        matched = nil
        router.pendingPersonaID = persona.id
        router.tab = 2
    }

    private func applyFilter(_ new: DiscoverFilter) {
        filter = new
        deck = DemoProfile.all.filter { new.matches($0) && !swiped.contains($0.id) }
    }

    private func swipe(like: Bool) {
        guard let top = deck.first, !isAnimatingOut else { return }
        isAnimatingOut = true
        UIImpactFeedbackGenerator(style: like ? .medium : .light).impactOccurred()
        withAnimation(.easeOut(duration: 0.25)) {
            drag = CGSize(width: like ? 700 : -700, height: drag.height)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if like {
                liked.append(top)
                if personas.contains(where: { $0.name == top.name }) || Bool.random() {
                    Haptics.success()
                    matched = top
                }
            }
            swiped.insert(top.id)
            deck.removeFirst()
            drag = .zero
            isAnimatingOut = false
        }
    }
}

struct ProfileCard: View {
    let profile: DemoProfile
    let dragX: CGFloat
    var distanceKm: Double?

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: profile.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(profile.emoji)
                .font(.system(size: 150))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 80)

            LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(profile.name).font(.system(size: 32, weight: .bold))
                    Text("\(profile.age)").font(.system(size: 26))
                }
                Label(distanceKm.map { "\(profile.city) · \(Int($0.rounded())) km away" } ?? profile.city,
                      systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                Text(profile.bio)
                    .font(.callout)
                    .lineLimit(3)
            }
            .foregroundStyle(.white)
            .padding(20)

            stamp("LIKE", color: .green, angle: -14)
                .opacity(Double(max(0, min(dragX / 100, 1))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            stamp("NOPE", color: .red, angle: 14)
                .opacity(Double(max(0, min(-dragX / 100, 1))))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }

    private func stamp(_ text: String, color: Color, angle: Double) -> some View {
        Text(text)
            .font(.system(size: 34, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 4))
            .rotationEffect(.degrees(angle))
            .padding(28)
    }
}

#Preview {
    DiscoverView()
}
