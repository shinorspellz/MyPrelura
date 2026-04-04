import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Debug → trace DM push issues: FCM/APNs, WebSocket presence, and `chat_push` lines in the shared event log.
struct MessageChatPushTraceDebugView: View {
    @EnvironmentObject private var authService: AuthService
    @ObservedObject private var traceState = ChatPushTraceDebugState.shared
    @State private var permissionText = "…"
    @State private var chatPushEntries: [NotificationDebugLog.Entry] = []

    var body: some View {
        List {
            Section {
                Text(
                    "Message pushes need: notification permission, FCM token uploaded to the API, **Messages** ON in notification settings, and the server must enqueue FCM. "
                        + "WebSocket status is for realtime chat only; seeing **Disconnected** on the inbox screen is normal when no thread is open."
                )
                .font(.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .listRowBackground(Color.clear)
            } header: {
                Text("How DM push works")
            }

            Section {
                LabeledContent("Signed in") {
                    Text(authService.isAuthenticated ? "Yes" : "No")
                }
                LabeledContent("Notification permission") {
                    Text(permissionText)
                }
                LabeledContent("Firebase") {
                    Text(FirebaseApp.app() != nil ? "Configured" : "Not configured")
                }
                LabeledContent("APNs token (for FCM)") {
                    Text(apnsLine)
                }
                LabeledContent("FCM token stored") {
                    Text(fcmStoredLine)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Device")
            }

            Section {
                LabeledContent("WebSocket (chat)") {
                    Text(traceState.socketConnected ? "Connected" : "Disconnected")
                }
                if let t = traceState.lastConnectAttemptAt {
                    LabeledContent("Last connect attempt") {
                        Text(t.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                    }
                }
                if let id = traceState.lastConnectAttemptConversationId {
                    LabeledContent("Attempted conv id") {
                        Text(id).font(.caption).textSelection(.enabled)
                    }
                }
                if let id = traceState.activeConversationId {
                    LabeledContent("Active conv id") {
                        Text(id).font(.caption).textSelection(.enabled)
                    }
                }
                if let t = traceState.lastConnectAt {
                    LabeledContent("Last connect") {
                        Text(t.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                    }
                }
                if let t = traceState.lastDisconnectAt {
                    LabeledContent("Last disconnect") {
                        Text(t.formatted(date: .abbreviated, time: .standard))
                            .font(.caption)
                    }
                }
                if let r = traceState.lastDisconnectReason {
                    Text(r)
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                if let traffic = traceState.lastTrafficSummary, let t = traceState.lastTrafficAt {
                    Text("Last traffic: \(traffic) at \(t.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } header: {
                Text("Realtime chat socket")
            } footer: {
                Text("Disconnected here while a thread is open indicates socket failure. Check latest connect attempt, close reason, and traffic rows to pinpoint if handshake or stream is failing.")
            }

            Section {
                NavigationLink("Open Push diagnostics") {
                    PushDiagnosticsView()
                        .environmentObject(authService)
                }
            }

            Section {
                if chatPushEntries.isEmpty {
                    Text("No `chat_push` lines yet. Open a chat (connect) and leave it (disconnect), or receive a message notification.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                } else {
                    ForEach(chatPushEntries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.at)
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            Text(entry.message)
                                .font(.caption)
                                .foregroundStyle(entry.isError ? Color.red : Theme.Colors.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                }
                Button("Copy chat_push trace") {
                    let text = chatPushEntries.map { "[\($0.at)] \($0.message)" }.joined(separator: "\n")
                    UIPasteboard.general.string = text.isEmpty ? "(empty)" : text
                }
            } header: {
                Text("chat_push event log")
            } footer: {
                Button("Clear all notification debug log", role: .destructive) {
                    NotificationDebugLog.clear()
                    reloadChatPushEntries()
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Message push trace")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadPermission()
            reloadChatPushEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraNotificationDebugLogDidChange)) { _ in
            reloadChatPushEntries()
        }
    }

    private var apnsLine: String {
        guard FirebaseApp.app() != nil else { return "N/A" }
        let t = Messaging.messaging().apnsToken
        if let t, !t.isEmpty { return "OK (\(t.count) bytes)" }
        return "Missing — remote push may not work until APNs registers"
    }

    private var fcmStoredLine: String {
        guard let s = UserDefaults.standard.string(forKey: kDeviceTokenKey), !s.isEmpty else {
            return "(none)"
        }
        if s.count <= 24 { return s }
        return "\(s.prefix(12))…\(s.suffix(8)) (\(s.count) chars)"
    }

    private func reloadPermission() {
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
            DispatchQueue.main.async { permissionText = t }
        }
    }

    private func reloadChatPushEntries() {
        chatPushEntries = NotificationDebugLog.entries().filter { $0.source == "chat_push" }
    }
}
