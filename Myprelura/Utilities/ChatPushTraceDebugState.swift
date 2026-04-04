import Combine
import Foundation

/// Debug-only: tracks chat WebSocket presence for DM troubleshooting.
@MainActor
final class ChatPushTraceDebugState: ObservableObject {
    static let shared = ChatPushTraceDebugState()

    @Published private(set) var activeConversationId: String?
    @Published private(set) var socketConnected: Bool
    @Published private(set) var lastConnectAt: Date?
    @Published private(set) var lastDisconnectAt: Date?
    @Published private(set) var lastDisconnectReason: String?
    @Published private(set) var lastConnectAttemptAt: Date?
    @Published private(set) var lastConnectAttemptConversationId: String?
    @Published private(set) var lastTrafficAt: Date?
    @Published private(set) var lastTrafficSummary: String?

    private init() {
        activeConversationId = nil
        socketConnected = false
        lastConnectAt = nil
        lastDisconnectAt = nil
        lastDisconnectReason = nil
        lastConnectAttemptAt = nil
        lastConnectAttemptConversationId = nil
        lastTrafficAt = nil
        lastTrafficSummary = nil
    }

    func markSocketConnectAttempt(conversationId: String) {
        guard conversationId != "0" else { return }
        lastConnectAttemptAt = Date()
        lastConnectAttemptConversationId = conversationId
        NotificationDebugLog.append(
            source: "chat_push",
            message: "WebSocket CONNECTING conv=\(conversationId)",
            isError: false
        )
    }

    func markSocketConnected(conversationId: String) {
        guard conversationId != "0" else { return }
        activeConversationId = conversationId
        socketConnected = true
        lastConnectAt = Date()
        NotificationDebugLog.append(
            source: "chat_push",
            message: "WebSocket OPEN conv=\(conversationId)",
            isError: false
        )
    }

    func markSocketDisconnected(conversationId: String, reason: String) {
        lastDisconnectAt = Date()
        lastDisconnectReason = reason
        activeConversationId = nil
        socketConnected = false
        NotificationDebugLog.append(
            source: "chat_push",
            message: "WebSocket CLOSED conv=\(conversationId) — \(reason)",
            isError: false
        )
    }

    func markSocketTraffic(conversationId: String, summary: String) {
        lastTrafficAt = Date()
        lastTrafficSummary = summary
        NotificationDebugLog.append(
            source: "chat_push",
            message: "WebSocket EVENT conv=\(conversationId) — \(summary)",
            isError: false
        )
    }

    /// Parse / transport issues (JSON, dropped chat frames). Shown in notification debug + OSLog on device.
    func markSocketDiagnostic(conversationId: String, summary: String, isError: Bool) {
        guard conversationId != "0" else { return }
        lastTrafficAt = Date()
        lastTrafficSummary = summary
        NotificationDebugLog.append(
            source: "chat_ws_diag",
            message: "conv=\(conversationId) — \(summary)",
            isError: isError
        )
    }
}
