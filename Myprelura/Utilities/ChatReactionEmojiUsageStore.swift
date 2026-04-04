import Combine
import Foundation

/// Persists how often the user picks each reaction emoji so the long-press quick bar can surface favorites first.
@MainActor
final class ChatReactionEmojiUsageStore: ObservableObject {
    static let shared = ChatReactionEmojiUsageStore()

    /// Red heart used for double-tap toggle (must match quick bar / picker strings for consistent toggling).
    static let doubleTapHeartEmoji = "❤️"

    private let ud = UserDefaults.standard
    private let storageKey = "chatReactionEmojiUsage_v1"

    private struct Persisted: Codable {
        var counts: [String: Int]
        var lastUsed: [String: TimeInterval]
    }

    private init() {}

    private func load() -> Persisted {
        guard let data = ud.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else {
            return Persisted(counts: [:], lastUsed: [:])
        }
        return decoded
    }

    private func save(_ p: Persisted) {
        if let data = try? JSONEncoder().encode(p) {
            ud.set(data, forKey: storageKey)
        }
        objectWillChange.send()
    }

    /// Call whenever the user applies a reaction (quick bar, extended picker, or double-tap).
    func recordUse(_ emoji: String) {
        let key = Self.canonicalEmojiKey(emoji)
        guard !key.isEmpty else { return }
        var p = load()
        p.counts[key, default: 0] += 1
        p.lastUsed[key] = Date().timeIntervalSince1970
        save(p)
    }

    /// Quick bar: most-used emojis first (including any picked from the extended sheet), then fill from `defaults` order.
    func orderedQuickReactions(defaults: [String], maxVisible: Int = 12) -> [String] {
        let p = load()
        let rankedUsed = p.counts.keys
            .filter { (p.counts[$0] ?? 0) > 0 }
            .sorted { a, b in
                let ca = p.counts[a] ?? 0
                let cb = p.counts[b] ?? 0
                if ca != cb { return ca > cb }
                return (p.lastUsed[a] ?? 0) > (p.lastUsed[b] ?? 0)
            }
        var out: [String] = []
        var seen = Set<String>()
        for e in rankedUsed {
            guard out.count < maxVisible else { break }
            let canon = Self.canonicalEmojiKey(e)
            guard !canon.isEmpty, seen.insert(canon).inserted else { continue }
            out.append(canon)
        }
        for e in defaults {
            guard out.count < maxVisible else { break }
            let canon = Self.canonicalEmojiKey(e)
            guard !canon.isEmpty, seen.insert(canon).inserted else { continue }
            out.append(canon)
        }
        return out
    }

    private static func canonicalEmojiKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
