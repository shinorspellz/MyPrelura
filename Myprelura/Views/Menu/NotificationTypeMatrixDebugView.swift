import SwiftUI
import UserNotifications

/// Debug matrix: what notification categories/pages exist and whether app routing is implemented.
struct NotificationTypeMatrixDebugView: View {
    @EnvironmentObject private var authService: AuthService
    @State private var permissionText: String = "…"
    @State private var pushEnabledText: String = "…"
    @State private var subPrefs: NotificationSubPreferences?
    @State private var loadError: String?

    private let service = NotificationService()

    private let preferenceRows: [(String, KeyPath<NotificationSubPreferences, Bool>)] = [
        ("likes", \.likes),
        ("messages", \.messages),
        ("new_followers", \.newFollowers),
        ("profile_view", \.profileView)
    ]

    private let pageRouteRows: [(String, String)] = [
        ("PRODUCT / PRODUCT_FLAG / LISTING", "Item detail"),
        ("USER / PROFILE / FOLLOW", "User profile"),
        ("CONVERSATION / MESSAGE / CHAT / OFFER", "Chat thread"),
        ("ORDER", "Order chat (if conversation_id) or order details"),
        ("ORDER_ISSUE", "Help chat (if conversation_id) or order details")
    ]

    var body: some View {
        List {
            Section {
                Text("Use this matrix to verify category toggles and page routing without guessing. For each failed push, compare the payload `page` and category with this screen.")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            } header: {
                Text("How to use")
            }

            Section {
                LabeledContent("Signed in") { Text(authService.isAuthenticated ? "Yes" : "No") }
                LabeledContent("Permission") { Text(permissionText) }
                LabeledContent("Push enabled") { Text(pushEnabledText) }
            } header: {
                Text("Device / account")
            }

            Section {
                if let prefs = subPrefs {
                    ForEach(preferenceRows, id: \.0) { row in
                        LabeledContent(row.0) {
                            Text(prefs[keyPath: row.1] ? "ON" : "OFF")
                                .foregroundStyle(prefs[keyPath: row.1] ? Color.green : Color.red)
                        }
                    }
                } else if let loadError {
                    Text(loadError)
                        .font(.caption)
                        .foregroundStyle(Color.red)
                } else {
                    ProgressView()
                }
            } header: {
                Text("Backend preference categories")
            } footer: {
                Text("These are the keys from notification settings. A category set OFF suppresses matching push sends.")
            }

            Section {
                ForEach(pageRouteRows, id: \.0) { row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.0)
                            .font(.subheadline.weight(.semibold))
                        Text(row.1)
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("FCM payload page routes implemented")
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Notification matrix")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadState()
        }
        .refreshable {
            await loadState()
        }
    }

    private func loadState() async {
        if let token = authService.authToken {
            service.updateAuthToken(token)
        }
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let t: String
                switch s.authorizationStatus {
                case .authorized: t = "Authorized"
                case .denied: t = "Denied"
                case .notDetermined: t = "Not determined"
                case .provisional: t = "Provisional"
                case .ephemeral: t = "Ephemeral"
                @unknown default: t = "Unknown"
                }
                DispatchQueue.main.async {
                    permissionText = t
                    continuation.resume()
                }
            }
        }
        do {
            let pref = try await service.getNotificationPreference()
            await MainActor.run {
                pushEnabledText = pref.isPushNotification ? "ON" : "OFF"
                subPrefs = pref.inappNotifications
                loadError = nil
            }
        } catch {
            await MainActor.run {
                loadError = error.localizedDescription
                pushEnabledText = "Unknown"
            }
        }
    }
}

