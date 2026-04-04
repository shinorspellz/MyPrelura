import Foundation

/// Builds a large single-codepoint emoji set and supports search via `Unicode.Scalar` annotation names (same data the system emoji keyboard uses for names).
enum EmojiReactionCatalog {
    /// Single-scalar emoji suitable for reactions (ZWJ sequences / flags omitted; still covers most keyboard glyphs).
    static let allEmojisForPicker: [String] = buildAllEmojis()

    private static func buildAllEmojis() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        let ranges: [ClosedRange<UInt32>] = [
            0x00A9...0x00AE,
            0x203C...0x3299,
            0x231A...0x23FA,
            0x2460...0x24FF,
            0x25AA...0x25FE,
            0x2600...0x27BF,
            0x2934...0x2B55,
            0x3030...0x303D,
            0x3297...0x3299,
            0x1F004...0x1F0CF,
            0x1F170...0x1F251,
            0x1F300...0x1FAFF,
        ]
        for range in ranges {
            for v in range {
                guard let scalar = UnicodeScalar(v) else { continue }
                let p = scalar.properties
                guard p.isEmoji else { continue }
                if p.isEmojiModifier { continue }
                if let name = p.name {
                    if name.contains("REGIONAL INDICATOR") { continue }
                    if name.contains("TAG ") || name.hasSuffix(" TAG") { continue }
                }
                if p.generalCategory == .format { continue }
                let s = String(Character(scalar))
                if seen.insert(s).inserted {
                    out.append(s)
                }
            }
        }
        return out.sorted {
            let na = $0.unicodeScalars.first?.properties.name ?? ""
            let nb = $1.unicodeScalars.first?.properties.name ?? ""
            if na != nb { return na < nb }
            return $0 < $1
        }
    }

    static func emojiMatchesSearch(_ emoji: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return true }
        for sc in emoji.unicodeScalars {
            if let name = sc.properties.name, name.lowercased().contains(q) { return true }
        }
        return false
    }
}
