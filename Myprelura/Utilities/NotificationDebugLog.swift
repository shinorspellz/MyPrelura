import Foundation

extension Notification.Name {
    /// Posted when the notification debug trace changes (Menu → Push diagnostics should refresh).
    static let preluraNotificationDebugLogDidChange = Notification.Name("PreluraNotificationDebugLogDidChange")
}

/// Ring buffer of push-related events (errors, arrivals, API outcomes) for Menu → Debug → Push diagnostics.
/// Survives app restarts so TestFlight users can screenshot history for support.
enum NotificationDebugLog {
    struct Entry: Codable, Identifiable, Equatable {
        var id: String
        var at: String
        var source: String
        var message: String
        var isError: Bool
    }

    private static let storageKey = "prelura_notification_debug_log_v1"
    private static let maxEntries = 200
    private static let iso = ISO8601DateFormatter()

    /// Append one line. `message` is truncated for safety.
    static func append(source: String, message: String, isError: Bool = false) {
        var list = load()
        let e = Entry(
            id: UUID().uuidString,
            at: iso.string(from: Date()),
            source: String(source.prefix(32)),
            message: String(message.prefix(800)),
            isError: isError
        )
        list.insert(e, at: 0)
        if list.count > maxEntries {
            list = Array(list.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .preluraNotificationDebugLogDidChange, object: nil)
        }
    }

    static func entries() -> [Entry] {
        load()
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .preluraNotificationDebugLogDidChange, object: nil)
        }
    }

    private static func load() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        return decoded
    }
}
