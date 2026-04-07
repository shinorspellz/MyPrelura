import Foundation

/// In-app notification (matches Flutter NotificationModel / GraphQL NotificationType).
struct AppNotification: Identifiable {
    let id: String
    let sender: NotificationSender?
    let message: String
    let model: String
    let modelId: String?
    let modelGroup: String?
    let isRead: Bool
    let createdAt: Date?
    let meta: [String: String]?

    struct NotificationSender {
        let username: String?
        let profilePictureUrl: String?
    }
}

extension AppNotification {
    /// Chat / DM rows stay off the home bell until unread this long (inbox holds fresh counts).
    private static let chatNotificationMinAgeToShow: TimeInterval = 30 * 60

    var isChatCentricNotification: Bool {
        (modelGroup ?? "").trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Chat") == .orderedSame
    }

    func shouldShowOnNotificationsPage(referenceDate: Date = Date()) -> Bool {
        guard isChatCentricNotification else { return true }
        if isRead { return false }
        guard let created = createdAt else { return true }
        return referenceDate.timeIntervalSince(created) >= Self.chatNotificationMinAgeToShow
    }

    var shouldCountTowardBellBadge: Bool {
        shouldShowOnNotificationsPage() && !isRead
    }
}
