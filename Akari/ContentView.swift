//
//  ContentView.swift
//  Akari
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var manager = ModelManager()
    @State private var router = AppRouter()

    var body: some View {
        Group {
            if manager.hasLoadedOnce {
                TabView(selection: $router.tab) {
                    HomeView()
                        .tabItem { Label("Home", systemImage: "house.fill") }
                        .tag(0)
                    DiscoverView()
                        .tabItem { Label("Discover", systemImage: "flame.fill") }
                        .tag(1)
                    PersonaListView()
                        .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right.fill") }
                        .tag(2)
                }
                .onChange(of: router.tab) { _, new in
                    Haptics.select()
                    TabBarWiggle.play(at: new)
                }
            } else {
                ModelSetupView()
            }
        }
        .environment(manager)
        .environment(router)
        .task { await manager.autoLoadIfDownloaded() }
    }
}

/// Plays the system wiggle symbol effect on the selected tab's icon in the real UITabBar.
enum TabBarWiggle {
    static func play(at index: Int, of count: Int = 3) {
        // Wait a beat so the bar has swapped in the selected icon.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard let bar = tabBar() else { return }
            // The bar may hold extra icon copies (e.g. for the selection highlight), so match by position:
            // animate every icon whose center falls inside the selected tab's slice of the bar.
            let slice = bar.bounds.width / CGFloat(count)
            let range = (slice * CGFloat(index))...(slice * CGFloat(index + 1))
            for icon in icons(in: bar) {
                let x = icon.convert(CGPoint(x: icon.bounds.midX, y: icon.bounds.midY), to: bar).x
                guard range.contains(x) else { continue }
                if #available(iOS 18.0, *) {
                    icon.addSymbolEffect(.wiggle)
                } else {
                    icon.addSymbolEffect(.bounce)
                }
            }
        }
    }

    private static func tabBar() -> UITabBar? {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        for window in windows {
            if let bar = find(UITabBar.self, in: window) { return bar }
        }
        return nil
    }

    /// One icon image view per tab button.
    private static func icons(in bar: UITabBar) -> [UIImageView] {
        var found: [UIImageView] = []
        func visit(_ v: UIView) {
            if let iv = v as? UIImageView, iv.image?.isSymbolImage == true, iv.bounds.width > 8, iv.bounds.width < 60 { found.append(iv); return }
            v.subviews.forEach(visit)
        }
        visit(bar)
        return found
    }

    private static func find<T: UIView>(_ type: T.Type, in view: UIView) -> T? {
        if let match = view as? T { return match }
        for sub in view.subviews { if let m = find(type, in: sub) { return m } }
        return nil
    }
}

#Preview {
    ContentView()
}
