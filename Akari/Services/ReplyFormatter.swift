import Foundation

/// Cleans raw model output and splits it into separate chat bubbles.
enum ReplyFormatter {
    private static let assistantisms = [
        "as an ai", "as a language model", "i'm just an ai", "i am an ai",
        "how can i assist", "how may i assist", "is there anything else i can help",
    ]

    static func bubbles(from raw: String, personaName: String? = nil, maxBubbles: Int = 3) -> [String] {
        var text = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop a leading "Name:" label if the model echoes one.
        if let name = personaName, text.lowercased().hasPrefix(name.lowercased() + ":") {
            text = String(text.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces)
        }

        var parts = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.replacingOccurrences(of: #"^[-*•]\s+"#, with: "", options: .regularExpression) }
            .filter { !$0.isEmpty }
            .filter { line in
                let l = line.lowercased()
                return !assistantisms.contains { l.contains($0) }
            }

        if parts.count > maxBubbles {
            let head = parts.prefix(maxBubbles - 1)
            let tail = parts.dropFirst(maxBubbles - 1).joined(separator: " ")
            parts = Array(head) + [tail]
        }
        return parts
    }

    /// Cleans a reply for text-to-speech: no markdown, emoji or "Name:" labels.
    static func spoken(_ raw: String, personaName: String? = nil) -> String {
        var text = raw
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "#", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let name = personaName, text.lowercased().hasPrefix(name.lowercased() + ":") {
            text = String(text.dropFirst(name.count + 1))
        }
        var scalars = String.UnicodeScalarView()
        for s in text.unicodeScalars {
            let isEmoji = s.properties.isEmojiPresentation || (s.properties.isEmoji && s.value > 0x2000)
            if isEmoji || s.value == 0xFE0F || s.value == 0x200D { continue }
            scalars.append(s)
        }
        return String(scalars)
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Simulated typing time for a bubble.
    static func typingDelay(for text: String) -> Duration {
        let base = 0.5 + Double(text.count) * 0.03
        let jitter = Double.random(in: 0...0.5)
        return .milliseconds(Int(min(base + jitter, 3.5) * 1000))
    }
}
