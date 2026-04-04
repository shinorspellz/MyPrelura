import Combine
import Foundation

extension Notification.Name {
    static let chatMessageReactionsDidChange = Notification.Name("ChatMessageReactionsDidChange")
}

/// Local-only message reactions (per device). Keys are stable: `b:<backendId>` when known, else `u:<client UUID>`.
@MainActor
final class ChatMessageReactionsStore: ObservableObject {
    static let shared = ChatMessageReactionsStore()

    private let ud = UserDefaults.standard
    private let prefix = "chatMsgReactions_v1."

    private init() {}

    private func storageKey(_ conversationId: String) -> String {
        prefix + conversationId
    }

    private func loadRaw(_ conversationId: String) -> [String: [String: String]] {
        guard let data = ud.data(forKey: storageKey(conversationId)),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private func saveRaw(_ conversationId: String, _ raw: [String: [String: String]]) {
        if let data = try? JSONEncoder().encode(raw) {
            ud.set(data, forKey: storageKey(conversationId))
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: .chatMessageReactionsDidChange, object: conversationId)
    }

    static func stableKey(for message: Message) -> String {
        if let b = message.backendId { return "b:\(b)" }
        return "u:\(message.id.uuidString)"
    }

    func reactionsByUsername(conversationId: String, messageKey: String) -> [String: String] {
        loadRaw(conversationId)[messageKey] ?? [:]
    }

    /// Same emoji as current user’s reaction removes it; otherwise sets or replaces (WhatsApp-style single reaction per user).
    func applyReaction(conversationId: String, messageKey: String, username: String, emoji: String) {
        var raw = loadRaw(conversationId)
        var map = raw[messageKey] ?? [:]
        if map[username] == emoji {
            map[username] = nil
        } else {
            map[username] = emoji
        }
        map = map.filter { !$0.value.isEmpty }
        if map.isEmpty {
            raw.removeValue(forKey: messageKey)
        } else {
            raw[messageKey] = map
        }
        saveRaw(conversationId, raw)
    }

    func migrateMessageKey(conversationId: String, from oldKey: String, to newKey: String) {
        guard oldKey != newKey else { return }
        var raw = loadRaw(conversationId)
        guard let chunk = raw.removeValue(forKey: oldKey) else { return }
        var merged = raw[newKey] ?? [:]
        for (u, e) in chunk {
            merged[u] = e
        }
        raw[newKey] = merged
        saveRaw(conversationId, raw)
    }

    func removeReactions(for conversationId: String, messageKey: String) {
        var raw = loadRaw(conversationId)
        raw.removeValue(forKey: messageKey)
        saveRaw(conversationId, raw)
    }

    /// Merge a peer’s reaction from WebSocket (absolute set/clear — no toggle).
    func applyRemoteReaction(conversationId: String, messageKey: String, username: String, emoji: String?) {
        var raw = loadRaw(conversationId)
        var map = raw[messageKey] ?? [:]
        if let e = emoji, !e.isEmpty {
            map[username] = e
        } else {
            map[username] = nil
        }
        map = map.filter { !$0.value.isEmpty }
        if map.isEmpty {
            raw.removeValue(forKey: messageKey)
        } else {
            raw[messageKey] = map
        }
        saveRaw(conversationId, raw)
    }
}
