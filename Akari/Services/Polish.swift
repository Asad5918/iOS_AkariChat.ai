import SwiftUI
import UIKit

/// Central place for haptics so call sites stay one-liners.
enum Haptics {
    static func tap() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    static func pop() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.7) }
    static func select() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
}

/// "online" if there was activity in the last 5 minutes, otherwise "last seen 3 hours ago".
enum Presence {
    static func isOnline(since date: Date) -> Bool { Date().timeIntervalSince(date) < 300 }

    static func text(since date: Date) -> String {
        if isOnline(since: date) { return "online" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "last seen " + f.localizedString(for: date, relativeTo: Date())
    }
}

extension UIImage {
    /// Downscaled JPEG so photos stored in chat stay small.
    func akariJPEG(maxDimension: CGFloat = 1024, quality: CGFloat = 0.8) -> Data? {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return jpegData(compressionQuality: quality) }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format)
            .image { _ in draw(in: CGRect(origin: .zero, size: target)) }
            .jpegData(compressionQuality: quality)
    }
}

/// Springy press feedback for icon buttons.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
