import Foundation
import Observation
import UIKit

/// The app user's own profile ("You" tab). Stored as JSON in UserDefaults; the photo is a JPEG in Documents.
struct UserProfile: Codable, Equatable {
    enum Gender: String, Codable, CaseIterable, Identifiable {
        case unspecified, woman, man, nonBinary
        var id: String { rawValue }
        var title: String {
            switch self {
            case .unspecified: "Prefer not to say"
            case .woman: "Woman"
            case .man: "Man"
            case .nonBinary: "Non-binary"
            }
        }
    }

    var name = ""
    var emoji = "😎"
    var age: Int?
    var gender: Gender = .unspecified
    var city = ""
    var bio = ""
    var interests: [String] = []
    var hasPhoto = false

    var displayName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? "You" : name }
    var isEmpty: Bool { self == UserProfile(emoji: emoji, hasPhoto: hasPhoto) }

    /// Line added to the system prompt so personas know who they're talking to. Nil when there's nothing to say.
    var promptLine: String? {
        var parts: [String] = []
        let n = name.trimmingCharacters(in: .whitespaces)
        if !n.isEmpty { parts.append(n) }
        if let age { parts.append("\(age)") }
        switch gender {
        case .woman: parts.append("woman")
        case .man: parts.append("man")
        case .nonBinary: parts.append("non-binary")
        case .unspecified: break
        }
        let c = city.trimmingCharacters(in: .whitespaces)
        if !c.isEmpty { parts.append("from \(c)") }
        var line = parts.isEmpty ? "" : "About the person you're texting: " + parts.joined(separator: ", ") + "."
        let b = bio.trimmingCharacters(in: .whitespacesAndNewlines)
        if !b.isEmpty { line += (line.isEmpty ? "About the person you're texting: " : " ") + b }
        if !interests.isEmpty { line += (line.isEmpty ? "" : " ") + "Their interests: " + interests.joined(separator: ", ") + "." }
        if !n.isEmpty { line += " Use their name now and then, like a friend would." }
        return line.isEmpty ? nil : line
    }
}

@Observable
final class UserProfileStore {
    static let shared = UserProfileStore()
    private static let key = "userProfile"

    var profile: UserProfile {
        didSet { save() }
    }
    /// Bumped when the photo file changes so views reload it.
    private(set) var photoVersion = 0

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let p = try? JSONDecoder().decode(UserProfile.self, from: data) {
            profile = p
        } else {
            profile = UserProfile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    static var photoURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("profile.jpg")
    }

    var photo: UIImage? {
        _ = photoVersion
        return profile.hasPhoto ? UIImage(contentsOfFile: Self.photoURL.path) : nil
    }

    func setPhoto(_ image: UIImage?) {
        if let data = image?.akariJPEG(maxDimension: 800) {
            try? data.write(to: Self.photoURL, options: .atomic)
            profile.hasPhoto = true
        } else {
            try? FileManager.default.removeItem(at: Self.photoURL)
            profile.hasPhoto = false
        }
        photoVersion += 1
    }
}
