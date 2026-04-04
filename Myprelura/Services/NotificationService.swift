import Foundation

/// Sub-preferences for in-app or email (likes, messages, newFollowers, profileView). Matches Flutter NotificationsPreferenceInputType.
struct NotificationSubPreferences {
    var likes: Bool
    var messages: Bool
    var newFollowers: Bool
    var profileView: Bool
}

/// Full notification preference (push, email, inapp, email sub). Matches Flutter NotificationPreference / GraphQL NotificationPreferenceType.
struct NotificationPreference {
    var isPushNotification: Bool
    var isEmailNotification: Bool
    var inappNotifications: NotificationSubPreferences
    var emailNotifications: NotificationSubPreferences
}

/// Fetches in-app notifications and notification preference (matches Flutter notificationRepo).
final class NotificationService {
    private var client: GraphQLClient

    init(client: GraphQLClient? = nil) {
        self.client = client ?? GraphQLClient()
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
    }

    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }

    // MARK: - Notification preference (settings)

    func getNotificationPreference() async throws -> NotificationPreference {
        let query = """
        query NotificationPreference {
          notificationPreference {
            isPushNotification
            isEmailNotification
            inappNotifications
            emailNotifications
          }
        }
        """
        struct Payload: Decodable {
            let notificationPreference: RawPref?
        }
        struct RawPref: Decodable {
            let isPushNotification: Bool?
            let isEmailNotification: Bool?
            let inappNotifications: String?
            let emailNotifications: String?
        }
        let response: Payload = try await client.execute(query: query, variables: nil, responseType: Payload.self)
        guard let raw = response.notificationPreference else {
            throw NSError(domain: "NotificationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No notification preference"])
        }
        let inapp = parseSubPref(raw.inappNotifications) ?? NotificationSubPreferences(likes: true, messages: true, newFollowers: true, profileView: true)
        let email = parseSubPref(raw.emailNotifications) ?? NotificationSubPreferences(likes: true, messages: true, newFollowers: true, profileView: true)
        return NotificationPreference(
            isPushNotification: raw.isPushNotification ?? true,
            isEmailNotification: raw.isEmailNotification ?? true,
            inappNotifications: inapp,
            emailNotifications: email
        )
    }

    private func parseSubPref(_ jsonString: String?) -> NotificationSubPreferences? {
        guard let s = jsonString, !s.isEmpty, let data = s.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return NotificationSubPreferences(
            likes: (json["likes"] as? Bool) ?? true,
            messages: (json["messages"] as? Bool) ?? true,
            newFollowers: (json["new_followers"] as? Bool) ?? true,
            profileView: (json["profile_view"] as? Bool) ?? true
        )
    }

    private func subPrefToJson(_ sub: NotificationSubPreferences) -> [String: Any] {
        ["likes": sub.likes, "newFollowers": sub.newFollowers, "profileView": sub.profileView, "messages": sub.messages]
    }

    func updateNotificationPreference(isPushNotification: Bool? = nil, isEmailNotification: Bool? = nil, inappNotifications: NotificationSubPreferences? = nil, emailNotifications: NotificationSubPreferences? = nil) async throws {
        let current = try await getNotificationPreference()
        let push = isPushNotification ?? current.isPushNotification
        let email = isEmailNotification ?? current.isEmailNotification
        let inapp = inappNotifications ?? current.inappNotifications
        let emailSub = emailNotifications ?? current.emailNotifications
        let mutation = """
        mutation UpdateNotificationPreference($isPushNotification: Boolean!, $isEmailNotification: Boolean!, $isSilentModeOn: Boolean!, $inappNotification: NotificationsPreferenceInputType, $emailNotification: NotificationsPreferenceInputType) {
          updateNotificationPreference(
            isPushNotification: $isPushNotification,
            isEmailNotification: $isEmailNotification,
            isSilentModeOn: $isSilentModeOn,
            inappNotifications: $inappNotification,
            emailNotifications: $emailNotification
          ) {
            success
          }
        }
        """
        let inappDict = subPrefToJson(inapp)
        let emailDict = subPrefToJson(emailSub)
        let variables: [String: Any] = [
            "isPushNotification": push,
            "isEmailNotification": email,
            "isSilentModeOn": false,
            "inappNotification": inappDict,
            "emailNotification": emailDict
        ]
        struct Payload: Decodable {
            let updateNotificationPreference: UpdateResult?
        }
        struct UpdateResult: Decodable {
            let success: Bool?
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        if response.updateNotificationPreference?.success != true {
            throw NSError(domain: "NotificationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to update preference"])
        }
    }

    // MARK: - Notifications list

    /// Query notifications with pagination. Matches existing backend query Notifications(pageCount, pageNumber).
    func getNotifications(pageCount: Int = 15, pageNumber: Int = 1) async throws -> (notifications: [AppNotification], totalNumber: Int) {
        let query = """
        query Notifications($pageCount: Int, $pageNumber: Int) {
          notifications(pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            message
            model
            modelId
            modelGroup
            isRead
            createdAt
            meta
            sender {
              username
              profilePictureUrl
            }
          }
          notificationsTotalNumber
        }
        """
        struct Payload: Decodable {
            let notifications: [RawNotification]?
            let notificationsTotalNumber: Int?
        }
        struct RawNotification: Decodable {
            let id: String
            let message: String?
            let model: String?
            let modelId: String?
            let modelGroup: String?
            let isRead: Bool?
            let createdAt: String?
            let meta: String?
            let sender: RawSender?
            enum CodingKeys: String, CodingKey { case id, message, model, modelId, modelGroup, isRead, createdAt, meta, sender }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                let idValue: String
                if let s = try? c.decode(String.self, forKey: .id) { idValue = s }
                else if let i = try? c.decode(Int.self, forKey: .id) { idValue = String(i) }
                else { idValue = "" }
                id = idValue
                message = try c.decodeIfPresent(String.self, forKey: .message)
                model = try c.decodeIfPresent(String.self, forKey: .model)
                modelId = try c.decodeIfPresent(String.self, forKey: .modelId)
                modelGroup = try c.decodeIfPresent(String.self, forKey: .modelGroup)
                isRead = try c.decodeIfPresent(Bool.self, forKey: .isRead)
                createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
                meta = try c.decodeIfPresent(String.self, forKey: .meta)
                sender = try c.decodeIfPresent(RawSender.self, forKey: .sender)
            }
        }
        struct RawSender: Decodable {
            let username: String?
            let profilePictureUrl: String?
        }
        let variables: [String: Any] = ["pageCount": pageCount, "pageNumber": pageNumber]
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        let list = response.notifications ?? []
        let total = response.notificationsTotalNumber ?? 0
        let parsed = list.map { raw in
            let createdAt: Date? = {
                guard let s = raw.createdAt else { return nil }
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = iso.date(from: s) { return d }
                iso.formatOptions = [.withInternetDateTime]
                return iso.date(from: s)
            }()
            let metaDict: [String: String]? = {
                guard let s = raw.meta, !s.isEmpty, let data = s.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
                return json.mapValues { String(describing: $0) }
            }()
            return AppNotification(
                id: raw.id,
                sender: raw.sender.map { s in AppNotification.NotificationSender(username: s.username, profilePictureUrl: s.profilePictureUrl) },
                message: raw.message ?? "",
                model: raw.model ?? "",
                modelId: raw.modelId,
                modelGroup: raw.modelGroup,
                isRead: raw.isRead ?? false,
                createdAt: createdAt,
                meta: metaDict
            )
        }
        return (parsed, total)
    }
    
    /// Mark notifications as read. Matches Flutter readNotification(notificationIds).
    func readNotifications(notificationIds: [Int]) async throws -> Bool {
        guard !notificationIds.isEmpty else { return true }
        let mutation = """
        mutation ReadNotification($notificationId: [Int]) {
          readNotifications(notificationId: $notificationId) {
            success
          }
        }
        """
        let variables: [String: Any] = ["notificationId": notificationIds]
        struct Payload: Decodable { let readNotifications: ReadResult? }
        struct ReadResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        return response.readNotifications?.success ?? false
    }
    
    /// Delete a notification. Matches Flutter deleteNotification(notificationId).
    func deleteNotification(notificationId: Int) async throws -> Bool {
        let mutation = """
        mutation DeleteNotification($notificationId: Int!) {
          deleteNotification(notificationId: $notificationId) {
            success
          }
        }
        """
        let variables: [String: Any] = ["notificationId": notificationId]
        struct Payload: Decodable { let deleteNotification: DeleteResult? }
        struct DeleteResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        return response.deleteNotification?.success ?? false
    }

    // MARK: - Push notification device token (APNs)

    /// Register the APNs device token with the backend so the server can send push notifications to this device.
    /// Mutation name and arguments must match the backend schema (same as used by Flutter for FCM). If the backend uses a different mutation (e.g. savePushToken), update the mutation string below.
    func registerDeviceToken(token: String) async throws {
        guard !token.isEmpty else { return }
        let mutation = """
        mutation RegisterDeviceToken($token: String!, $platform: String!) {
          registerDevice(token: $token, platform: $platform) {
            success
          }
        }
        """
        let variables: [String: Any] = ["token": token, "platform": "ios"]
        struct Payload: Decodable {
            let registerDevice: Result?
            struct Result: Decodable { let success: Bool? }
        }
        do {
            let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
            if response.registerDevice?.success != true {
                throw NSError(domain: "NotificationService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to register device token"])
            }
        } catch {
            #if DEBUG
            print("Prelura: registerDeviceToken failed (backend may use a different mutation name): \(error)")
            #endif
            throw error
        }
    }
}
