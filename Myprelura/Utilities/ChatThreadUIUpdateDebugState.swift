import Combine
import Foundation

/// Debug-only: end-to-end trace for “notification arrived but chat thread didn’t update”.
/// Pipeline: WebSocket string → JSON route → parse → `onNewMessage` → bridge queue → SwiftUI `onChange` → `handleSocketIncomingChatMessage`.
@MainActor
final class ChatThreadUIUpdateDebugState: ObservableObject {
    static let shared = ChatThreadUIUpdateDebugState()

    struct LogEntry: Identifiable {
        let id = UUID()
        let at: Date
        let line: String
    }

    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var wsStringReceiveCount: Int = 0
    @Published private(set) var jsonObjectReceiveCount: Int = 0
    @Published private(set) var parseSuccessCount: Int = 0
    @Published private(set) var parseDropCount: Int = 0
    /// Django `receive_json` exception path sends `{"error": "..."}` — not a chat row; counted separately from parse drops.
    @Published private(set) var serverErrorFrameCount: Int = 0
    @Published private(set) var bridgeEmitCount: Int = 0
    @Published private(set) var uiOnChangeDrainCount: Int = 0
    @Published private(set) var uiHandlerOutcomeCount: Int = 0

    private let maxEntries = 100

    private init() {}

    func clear() {
        entries.removeAll()
        wsStringReceiveCount = 0
        jsonObjectReceiveCount = 0
        parseSuccessCount = 0
        parseDropCount = 0
        serverErrorFrameCount = 0
        bridgeEmitCount = 0
        uiOnChangeDrainCount = 0
        uiHandlerOutcomeCount = 0
    }

    /// Raw WebSocket text frame (before JSON parse).
    func recordWebSocketStringReceived(conversationId: String, byteLength: Int) {
        guard conversationId != "0" else { return }
        wsStringReceiveCount += 1
        push(
            "WS frame conv=\(conversationId) bytes=\(byteLength)",
            toNotificationLog: true
        )
    }

    func recordJsonReceived(conversationId: String, routingHint: String) {
        guard conversationId != "0" else { return }
        jsonObjectReceiveCount += 1
        push("WS JSON conv=\(conversationId) \(routingHint)", toNotificationLog: true)
    }

    func recordRoutedNonChat(conversationId: String, summary: String) {
        guard conversationId != "0" else { return }
        push("ROUTE (not chat row) conv=\(conversationId) \(summary)", toNotificationLog: true)
    }

    func recordParseDropped(conversationId: String, summary: String) {
        guard conversationId != "0" else { return }
        parseDropCount += 1
        push("PARSE DROP conv=\(conversationId) \(summary)", toNotificationLog: true, isError: true)
    }

    func recordServerSocketError(conversationId: String, redactedDetail: String) {
        guard conversationId != "0" else { return }
        serverErrorFrameCount += 1
        push("SERVER ERROR conv=\(conversationId) \(redactedDetail)", toNotificationLog: true, isError: true)
    }

    func recordParseDelivering(conversationId: String, backendId: String, textLen: Int, sender: String) {
        guard conversationId != "0" else { return }
        parseSuccessCount += 1
        let s = sender.count > 24 ? String(sender.prefix(24)) + "…" : sender
        push(
            "PARSE OK → onNewMessage conv=\(conversationId) bid=\(backendId) textLen=\(textLen) sender=\(s)",
            toNotificationLog: true
        )
    }

    func recordBridgeEmit(conversationId: String, sequence: UInt64, queueDepthAfterAppend: Int) {
        guard conversationId != "0" else { return }
        bridgeEmitCount += 1
        push(
            "BRIDGE enqueue conv=\(conversationId) seq=\(sequence) depth=\(queueDepthAfterAppend)",
            toNotificationLog: true
        )
    }

    func recordUIOnChangeDrained(conversationId: String, drainedCount: Int, firstBackendId: String?) {
        guard conversationId != "0" else { return }
        uiOnChangeDrainCount += 1
        let bid = firstBackendId ?? "nil"
        push(
            "UI onChange DRAIN conv=\(conversationId) count=\(drainedCount) firstBid=\(bid)",
            toNotificationLog: true
        )
    }

    /// Logged once per `handleSocketIncomingChatMessage` exit path (echo / merge / append / same-id).
    func recordUIHandlerOutcome(conversationId: String, backendId: Int?, outcome: String) {
        guard conversationId != "0" else { return }
        uiHandlerOutcomeCount += 1
        let b = backendId.map { String($0) } ?? "nil"
        push("UI OUTCOME conv=\(conversationId) bid=\(b) \(outcome)", toNotificationLog: true)
    }

    func exportText() -> String {
        let header = """
        wsFrames=\(wsStringReceiveCount) json=\(jsonObjectReceiveCount) parseOk=\(parseSuccessCount) parseDrop=\(parseDropCount) serverErr=\(serverErrorFrameCount) bridge=\(bridgeEmitCount) uiDrain=\(uiOnChangeDrainCount) uiOutcome=\(uiHandlerOutcomeCount)

        """
        let lines = entries.reversed().map { entry in
            let t = entry.at.formatted(date: .omitted, time: .standard)
            return "[\(t)] \(entry.line)"
        }
        return header + lines.joined(separator: "\n")
    }

    private func push(_ line: String, toNotificationLog: Bool, isError: Bool = false) {
        let entry = LogEntry(at: Date(), line: line)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries.removeLast(entries.count - maxEntries)
        }
        if toNotificationLog {
            NotificationDebugLog.append(source: "chat_ui_trace", message: line, isError: isError)
        }
    }
}
