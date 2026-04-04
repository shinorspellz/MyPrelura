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
