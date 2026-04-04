import Foundation
import OSLog

/// Event pushed when backend creates/updates an offer (Django Channels). When backend sends NEW_OFFER / UPDATE_OFFER, use this to update UI without refetch.
struct OfferSocketEvent {
    let type: String  // "NEW_OFFER" | "UPDATE_OFFER"
    let conversationId: String?
    let offer: OfferInfo?
    let offerId: String?
    let status: String?
    /// Explicit sender for offer events when backend provides it.
    let senderUsername: String?
}

/// Typing event pushed by backend while peer is composing a message.
struct TypingSocketEvent {
    let conversationId: String?
    let isTyping: Bool
    let senderUsername: String?
}

/// Order-related event pushed by backend (e.g. order_status_event, order_cancellation_event).
struct OrderSocketEvent {
    let type: String
    let conversationId: String?
    let orderId: Int?
}

/// Relayed chat message reaction from another participant (`message_reaction` on the socket).
struct MessageReactionSocketEvent {
    let messageId: Int
    /// Nil or empty means reaction removed for that user.
    let emoji: String?
    let username: String
}

/// WebSocket client for chat: connect to backend ws, send messages, receive new messages and events.
/// Uses same host as GraphQL (Constants.chatWebSocketBaseURL) so messages send/save to the same backend.
final class ChatWebSocketService: NSObject, @unchecked Sendable, URLSessionWebSocketDelegate {
    private static let diagLog = Logger(subsystem: "com.prelura.preloved", category: "ChatWS")
    private let conversationId: String
    private let token: String
    private var task: URLSessionWebSocketTask?
    private var session: URLSession?
    private var receiveTask: Task<Void, Error>?
    private let baseURL = Constants.chatWebSocketBaseURL
    private var didManualClose = false
    private(set) var isConnected: Bool = false

    /// Called on main actor when a new chat message is received. If server echoes our send, messageUuid is the client UUID we sent.
    var onNewMessage: (@MainActor (Message, String?) -> Void)?
    /// Called when backend pushes NEW_OFFER or UPDATE_OFFER (enables instant offer updates without refetch).
    var onOfferEvent: (@MainActor (OfferSocketEvent) -> Void)?
    /// Called when backend pushes typing events.
    var onTypingEvent: (@MainActor (TypingSocketEvent) -> Void)?
    /// Called when backend pushes order-related events.
    var onOrderEvent: (@MainActor (OrderSocketEvent) -> Void)?
    /// Called when connection state changes (e.g. for UI indicator).
    var onConnectionStateChanged: (@MainActor (Bool) -> Void)?
    /// Human-readable reason when socket closes/fails.
    var onDisconnectReason: (@MainActor (String) -> Void)?
    /// Another participant updated a message reaction (server type `message_reaction`).
    var onMessageReaction: (@MainActor (MessageReactionSocketEvent) -> Void)?
    /// Django consumer exception path: `{"error": "Error processing message: ..."}` (no `type` / not a chat row).
    var onServerSocketError: (@MainActor (String) -> Void)?

    init(conversationId: String, token: String) {
        self.conversationId = conversationId
        self.token = token
    }

    func connect() {
        guard let url = URL(string: baseURL + conversationId + "/") else { return }
        didManualClose = false
        isConnected = false
        var request = URLRequest(url: url)
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        self.session = session
        task = session.webSocketTask(with: request)
        task?.resume()
        receiveTask = Task {
            await receiveLoop()
        }
    }

    func disconnect() {
        didManualClose = true
        isConnected = false
        receiveTask?.cancel()
        receiveTask = nil
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
        session?.invalidateAndCancel()
        session = nil
        Task { @MainActor in
            onConnectionStateChanged?(false)
            onDisconnectReason?("manual_disconnect")
        }
    }

    /// Send a text message. Payload: {"message": text, "message_uuid": uuid}
    @discardableResult
    func send(message: String, messageUUID: String) -> Bool {
        guard let task = task else { return false }
        let payload: [String: Any] = ["message": message, "message_uuid": messageUUID]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return false }
        // Do not require `isConnected`: the handshake can still be in flight; the task queues outbound frames.
        task.send(.string(string)) { error in
            if let e = error {
                print("ChatWebSocket send error: \(e)")
            }
        }
        return true
    }

    /// Send typing state to backend, when supported by chat socket.
    /// Payload follows existing backend convention: {"is_typing": true/false}
    func sendTyping(isTyping: Bool) {
        guard task != nil else { return }
        // Send multiple commonly-used keys so backend variants can understand typing updates.
        let payload: [String: Any] = [
            "type": "typing",
            "is_typing": isTyping,
            "isTyping": isTyping,
            "conversation_id": conversationId,
            "conversationId": conversationId
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(string)) { error in
            if let e = error {
                print("ChatWebSocket typing send error: \(e)")
            }
        }
    }

    /// Notify room of reaction change; server broadcasts `message_reaction` to all participants.
    func sendMessageReaction(messageId: Int, emoji: String?) {
        var payload: [String: Any] = [
            "type": "message_reaction",
            "message_id": messageId,
            "conversation_id": conversationId,
        ]
        if let e = emoji, !e.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            payload["emoji"] = e
        } else {
            payload["remove"] = true
        }
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let string = String(data: data, encoding: .utf8) else { return }
        task?.send(.string(string)) { error in
            if let e = error {
                print("ChatWebSocket reaction send error: \(e)")
            }
        }
    }

    private func receiveLoop() async {
        guard let task = task else { return }
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    await handleReceivedString(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        await handleReceivedString(text)
                    }
                @unknown default:
                    break
                }
            } catch {
                if (error as NSError).code != NSURLErrorCancelled {
                    print("ChatWebSocket receive error: \(error)")
                    await MainActor.run {
                        if !didManualClose {
                            isConnected = false
                            onConnectionStateChanged?(false)
                            onDisconnectReason?("receive_error: \(error.localizedDescription)")
                        }
                    }
                }
                break
            }
        }
    }

    // MARK: - URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        Task { @MainActor in
            isConnected = true
            onConnectionStateChanged?(true)
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        let reasonText: String = {
            if let reason, let s = String(data: reason, encoding: .utf8), !s.isEmpty {
                return "closed(\(closeCode.rawValue)): \(s)"
            }
            return "closed(\(closeCode.rawValue))"
        }()
        Task { @MainActor in
            if !didManualClose {
                isConnected = false
                onConnectionStateChanged?(false)
                onDisconnectReason?(reasonText)
            }
        }
    }

    /// JSON may send conversation id as String or Int.
    private static func jsonString(_ value: Any?) -> String? {
        switch value {
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        case let i as Int:
            return String(i)
        case let n as NSNumber:
            return n.stringValue
        default:
            return nil
        }
    }

    /// True when JSON has a non-null message primary key. Chat broadcasts include this even after the server strips `type: chat_message`.
    private static func hasPersistedMessageId(_ json: [String: Any]) -> Bool {
        guard let raw = json["id"] else { return false }
        return !(raw is NSNull)
    }

    /// JSON may use Bool, 0/1, or NSNumber from mixed encoders.
    private static func coerceTypingFlag(_ value: Any?) -> Bool? {
        switch value {
        case let b as Bool:
            return b
        case let i as Int:
            return i != 0
        case let n as NSNumber:
            return n.boolValue
        case let s as String:
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" || t == "1" || t == "yes" { return true }
            if t == "false" || t == "0" || t == "no" { return false }
            return nil
        default:
            return nil
        }
    }

    /// True when `is_typing` / `isTyping` exists and is not JSON null (`dict[key] != nil` is true for NSNull, which must not count as typing).
    private static func jsonHasNonNullTypingFlag(_ json: [String: Any]) -> Bool {
        if let v = json["is_typing"], !(v is NSNull) { return true }
        if let v = json["isTyping"], !(v is NSNull) { return true }
        return false
    }

    /// Matches Flutter `messages_provider.dart`: only treat a frame as a chat row when `is_typing` is absent or JSON-null (not `false`).
    private static func flutterTypingKeyIsAbsentOrNull(_ json: [String: Any]) -> Bool {
        let v = json["is_typing"] ?? json["isTyping"]
        return v == nil || v is NSNull
    }

    /// True when the dict looks like a persisted/plain chat line (not offer-only envelopes).
    private static func looksLikeChatRowPayload(_ json: [String: Any]) -> Bool {
        if hasPersistedMessageId(json) { return true }
        let t = coerceSocketText(json).trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty
    }

    private func deliverParsedChatMessage(json: [String: Any], convId: String) async {
        guard let msg = parseWebSocketMessage(json) else {
            let summary = Self.jsonKeySummary(json)
            Self.diagLog.error("chat_frame_dropped conv=\(convId, privacy: .public) \(summary, privacy: .public)")
            print("[ChatWS] chat_frame_dropped conv=\(convId) \(summary)")
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordParseDropped(conversationId: convId, summary: summary)
                ChatPushTraceDebugState.shared.markSocketDiagnostic(
                    conversationId: convId,
                    summary: "chat_frame_dropped \(summary)",
                    isError: true
                )
            }
            return
        }
        let echoUuid = (json["message_uuid"] as? String) ?? (json["messageUuid"] as? String)
        let bid = msg.backendId.map { String($0) } ?? "nil"
        Self.diagLog.info("chat_message_parsed conv=\(convId, privacy: .public) backendId=\(bid, privacy: .public) sender=\(msg.senderUsername, privacy: .public) type=\(msg.type, privacy: .public) textLen=\(msg.content.count)")
        print("[ChatWS] chat_message_parsed conv=\(convId) backendId=\(bid) sender=\(msg.senderUsername) type=\(msg.type) textLen=\(msg.content.count)")
        await MainActor.run {
            ChatThreadUIUpdateDebugState.shared.recordParseDelivering(
                conversationId: convId,
                backendId: bid,
                textLen: msg.content.count,
                sender: msg.senderUsername
            )
            onNewMessage?(msg, echoUuid)
        }
    }

    private func handleReceivedString(_ text: String) async {
        let convId = conversationId
        await MainActor.run {
            ChatThreadUIUpdateDebugState.shared.recordWebSocketStringReceived(conversationId: convId, byteLength: text.utf8.count)
        }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = Self.redactForLog(text, maxLen: 200)
            Self.diagLog.error("json_parse_failed conv=\(convId, privacy: .public) len=\(text.count) preview=\(preview, privacy: .public)")
            print("[ChatWS] json_parse_failed conv=\(convId) len=\(text.count) preview=\(preview)")
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordParseDropped(conversationId: convId, summary: "json_parse_failed len=\(text.count)")
                ChatPushTraceDebugState.shared.markSocketDiagnostic(
                    conversationId: convId,
                    summary: "json_parse_failed len=\(text.count)",
                    isError: true
                )
            }
            return
        }
        await MainActor.run {
            ChatThreadUIUpdateDebugState.shared.recordJsonReceived(
                conversationId: convId,
                routingHint: Self.debugRoutingHint(json)
            )
        }
        let type = json["type"] as? String
        let typeNorm = type?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if typeNorm != "chat_message",
           let errRaw = json["error"] as? String,
           !errRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let redacted = Self.redactForLog(errRaw, maxLen: 180)
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordServerSocketError(
                    conversationId: convId,
                    redactedDetail: redacted
                )
                ChatPushTraceDebugState.shared.markSocketDiagnostic(
                    conversationId: convId,
                    summary: "server_error \(redacted)",
                    isError: true
                )
                onServerSocketError?(errRaw)
            }
            return
        }
        if typeNorm == "order_issue_created" || typeNorm == "order_status_event" || typeNorm == "order_cancellation_event" {
            let payloadConvId = (json["conversationId"] as? String) ?? (json["conversation_id"] as? String)
            let oid = (json["order_id"] as? Int)
                ?? (json["orderId"] as? Int)
                ?? ((json["order_id"] as? String).flatMap { Int($0) })
                ?? ((json["orderId"] as? String).flatMap { Int($0) })
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(
                    conversationId: convId,
                    summary: "order_event type=\(type ?? "") payloadConv=\(payloadConvId ?? "nil")"
                )
                onOrderEvent?(OrderSocketEvent(type: type ?? "", conversationId: payloadConvId, orderId: oid))
            }
            return
        }
        if typeNorm == "message_reaction" {
            let mid = (json["message_id"] as? Int)
                ?? (json["messageId"] as? Int)
                ?? ((json["message_id"] as? String).flatMap { Int($0) })
                ?? ((json["messageId"] as? String).flatMap { Int($0) })
            let rawEmoji = (json["emoji"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let emoji = rawEmoji.isEmpty ? nil : rawEmoji
            let username = ((json["username"] as? String) ?? (json["sender"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let mid {
                let ev = MessageReactionSocketEvent(messageId: mid, emoji: emoji, username: username)
                await MainActor.run {
                    ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(conversationId: convId, summary: "message_reaction id=\(mid)")
                    onMessageReaction?(ev)
                }
            }
            return
        }
        // Pebble/Flutter: treat `type: chat_message` as a row payload first (never as typing), same as messages_provider.dart.
        if typeNorm == "chat_message" {
            await deliverParsedChatMessage(json: json, convId: convId)
            return
        }
        // Typing: server sends `type: typing_status`; clients may send `type: typing` + is_typing / isTyping.
        let explicitTyping = typeNorm == "typing_status" || typeNorm == "typing"
        if explicitTyping {
            let typingConvId = Self.jsonString(json["conversationId"])
                ?? Self.jsonString(json["conversation_id"])
            let isTyping = Self.coerceTypingFlag(json["is_typing"]) ?? Self.coerceTypingFlag(json["isTyping"]) ?? true
            let rawSender = (json["senderUsername"] as? String)
                ?? (json["sender_username"] as? String)
                ?? (json["senderName"] as? String)
                ?? (json["sender_name"] as? String)
                ?? (json["sender"] as? String)
                ?? (json["username"] as? String)
            let senderUsername = rawSender?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(
                    conversationId: convId,
                    summary: "typing explicit type=\(typeNorm ?? "") typingConv=\(typingConvId ?? "nil") isTyping=\(isTyping)"
                )
                onTypingEvent?(TypingSocketEvent(conversationId: typingConvId, isTyping: isTyping, senderUsername: senderUsername))
            }
            return
        }
        // Flutter: only ingest chat rows when `is_typing == null` (absent or JSON null). Do this before legacy typing
        // so optional `is_typing` keys on mixed payloads do not swallow real messages.
        let offerEnvelopeTypes: Set<String> = ["offer_status_event", "new_offer", "update_offer"]
        if let tn = typeNorm, !offerEnvelopeTypes.contains(tn),
           Self.flutterTypingKeyIsAbsentOrNull(json),
           Self.looksLikeChatRowPayload(json),
           parseWebSocketMessage(json) != nil {
            await deliverParsedChatMessage(json: json, convId: convId)
            return
        }
        let legacyTypingPayload =
            (typeNorm == nil || typeNorm != "chat_message")
            && !Self.hasPersistedMessageId(json)
            && Self.jsonHasNonNullTypingFlag(json)
        if legacyTypingPayload {
            let typingConvId = Self.jsonString(json["conversationId"])
                ?? Self.jsonString(json["conversation_id"])
            let isTyping = Self.coerceTypingFlag(json["is_typing"]) ?? Self.coerceTypingFlag(json["isTyping"]) ?? true
            let rawSender = (json["senderUsername"] as? String)
                ?? (json["sender_username"] as? String)
                ?? (json["senderName"] as? String)
                ?? (json["sender_name"] as? String)
                ?? (json["sender"] as? String)
                ?? (json["username"] as? String)
            let senderUsername = rawSender?.trimmingCharacters(in: .whitespacesAndNewlines)
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(
                    conversationId: convId,
                    summary: "typing legacy typingConv=\(typingConvId ?? "nil") isTyping=\(isTyping)"
                )
                onTypingEvent?(TypingSocketEvent(conversationId: typingConvId, isTyping: isTyping, senderUsername: senderUsername))
            }
            return
        }
        // Django backend sends offer_status_event with nested `offer` + sender_username (see prelura-app offer_utils).
        if typeNorm == "offer_status_event" {
            let offerPayloadConvId = (json["conversationId"] as? String) ?? (json["conversation_id"] as? String)
            let offerJson = json["offer"] as? [String: Any]
            // Prefer top-level; fall back to nested offer (backend now sends senderUsername in both).
            let senderUsername = (json["senderUsername"] as? String)
                ?? (json["sender_username"] as? String)
                ?? (json["senderName"] as? String)
                ?? (json["sender_name"] as? String)
                ?? (offerJson?["senderUsername"] as? String)
                ?? (offerJson?["sender_username"] as? String)
            let offerId = (json["offerId"] as? String) ?? (json["offer_id"] as? String) ?? (json["offer_id"] as? Int).map { String($0) }
            let status = json["status"] as? String
            if offerJson != nil {
                let offer = parseOfferFromSocket(offerJson)
                await MainActor.run {
                    ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(conversationId: convId, summary: "offer_status_event payloadConv=\(offerPayloadConvId ?? "nil")")
                    onOfferEvent?(OfferSocketEvent(type: "NEW_OFFER", conversationId: offerPayloadConvId, offer: offer, offerId: offerId, status: status, senderUsername: senderUsername))
                }
            } else {
                await MainActor.run {
                    ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(conversationId: convId, summary: "offer_status_event UPDATE payloadConv=\(offerPayloadConvId ?? "nil")")
                    onOfferEvent?(OfferSocketEvent(type: "UPDATE_OFFER", conversationId: offerPayloadConvId, offer: nil, offerId: offerId, status: status, senderUsername: senderUsername))
                }
            }
            return
        }
        // Offer events: optional explicit NEW_OFFER / UPDATE_OFFER (same payload shape).
        if type == "NEW_OFFER" || type == "UPDATE_OFFER" {
            let offerPayloadConvId = (json["conversationId"] as? String) ?? (json["conversation_id"] as? String)
            let offerJson = json["offer"] as? [String: Any]
            let offer = parseOfferFromSocket(offerJson)
            let offerId = (json["offerId"] as? String) ?? (json["offer_id"] as? String) ?? (json["offerId"] as? Int).map { String($0) }
            let status = json["status"] as? String
            // Only explicit top-level sender fields — never infer from offer.buyer (buyer is stable; counters would mis-attribute).
            let senderUsername = (json["senderUsername"] as? String)
                ?? (json["sender_username"] as? String)
                ?? (json["senderName"] as? String)
                ?? (json["sender_name"] as? String)
            await MainActor.run {
                ChatThreadUIUpdateDebugState.shared.recordRoutedNonChat(conversationId: convId, summary: "offer_envelope \(type ?? "") payloadConv=\(offerPayloadConvId ?? "nil")")
                onOfferEvent?(OfferSocketEvent(type: type ?? "", conversationId: offerPayloadConvId, offer: offer, offerId: offerId, status: status, senderUsername: senderUsername))
            }
            return
        }
        // New message: parse and notify on main actor (messageUuid when server confirms our send).
        await deliverParsedChatMessage(json: json, convId: convId)
    }

    private static func debugRoutingHint(_ json: [String: Any]) -> String {
        let t = (json["type"] as? String) ?? "(nil)"
        let rawId = json["id"]
        let hasId = rawId != nil && !(rawId is NSNull)
        let tl = coerceSocketText(json).count
        let typingKey = json["is_typing"] ?? json["isTyping"]
        let tk: String
        if typingKey == nil { tk = "absent" }
        else if typingKey is NSNull { tk = "null" }
        else { tk = "set" }
        return "type=\(t) hasId=\(hasId) textLen=\(tl) typingKey=\(tk)"
    }

    private static func redactForLog(_ s: String, maxLen: Int) -> String {
        let t = s.replacingOccurrences(of: "\n", with: "\\n")
        if t.count <= maxLen { return t }
        return String(t.prefix(maxLen)) + "…"
    }

    /// Short summary when a dict is not a parseable chat message (missing id + empty text).
    private static func jsonKeySummary(_ json: [String: Any]) -> String {
        let keys = json.keys.sorted().joined(separator: ",")
        let hasId = json["id"] != nil
        let rawText = coerceSocketText(json)
        return "keys=[\(keys)] hasId=\(hasId) textLen=\(rawText.count)"
    }

    private static func coerceSocketText(_ json: [String: Any]) -> String {
        if let s = json["text"] as? String { return s }
        if let s = json["message"] as? String { return s }
        if let n = json["text"] as? NSNumber { return n.stringValue }
        if let n = json["message"] as? NSNumber { return n.stringValue }
        return ""
    }

    private static func coerceSocketSenderUsername(_ json: [String: Any]) -> String {
        let top = (json["senderName"] as? String) ?? (json["sender_name"] as? String)
        let trimmedTop = top?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedTop.isEmpty { return trimmedTop }
        if let sender = json["sender"] as? [String: Any],
           let u = sender["username"] as? String {
            return u.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    /// Parses `createdAt` / `created_at` from GraphQL ISO-8601 or Django `str(datetime)` (`"yyyy-MM-dd HH:mm:ss+00:00"`, optional fractional seconds).
    private static func parseSocketTimestamp(_ json: [String: Any]) -> Date {
        let raw = (json["createdAt"] as? String) ?? (json["created_at"] as? String)
        let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !s.isEmpty else { return Date() }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        for pattern in [
            "yyyy-MM-dd HH:mm:ss.SSSSSSXXX",
            "yyyy-MM-dd HH:mm:ss.SSSXXX",
            "yyyy-MM-dd HH:mm:ssXXX",
            "yyyy-MM-dd HH:mm:ss.SSSSSSZ",
            "yyyy-MM-dd HH:mm:ssZ",
        ] {
            df.dateFormat = pattern
            if let d = df.date(from: s) { return d }
        }
        return Date()
    }

    /// Parse server message JSON to Message (Flutter `MessageModel.fromSocket`: id, text, senderName/sender_name, createdAt, isItem, itemId, sender map).
    private func parseWebSocketMessage(_ json: [String: Any]) -> Message? {
        let text = Self.coerceSocketText(json)
        guard !text.isEmpty || json["id"] != nil else { return nil }
        let senderName = Self.coerceSocketSenderUsername(json)
        let backendInt = (json["id"] as? Int)
            ?? (json["id"] as? NSNumber).map { $0.intValue }
            ?? (json["id"] as? Double).map { Int($0) }
            ?? (json["id"] as? String).flatMap { Int($0) }
        let uuid: UUID = {
            if let b = backendInt { return Message.stableUUID(forBackendId: b) }
            let idStr = (json["id"] as? String) ?? UUID().uuidString
            return UUID(uuidString: idStr) ?? UUID()
        }()
        let createdAt = Self.parseSocketTimestamp(json)
        let isItem = (json["isItem"] as? Bool) ?? (json["is_item"] as? Bool) ?? false
        let itemType = (json["itemType"] as? String) ?? (json["item_type"] as? String)
        let itemId = (json["itemId"] as? Int).map { String($0) } ?? (json["item_id"] as? Int).map { String($0) }
        let messageType: String = (itemType?.isEmpty == false) ? itemType! : (isItem ? "item" : "text")
        let read = (json["read"] as? Bool) ?? false
        return Message(
            id: uuid,
            backendId: backendInt,
            senderUsername: senderName,
            content: text,
            timestamp: createdAt,
            type: messageType,
            orderID: itemId,
            thumbnailURL: nil,
            read: read
        )
    }

    /// Parse offer payload from NEW_OFFER socket event. Backend may send id, offerPrice, status, createdAt (timestamp).
    private func parseOfferFromSocket(_ offerJson: [String: Any]?) -> OfferInfo? {
        guard let o = offerJson else { return nil }
        let id = (o["id"] as? Int).map { String($0) } ?? (o["id"] as? String) ?? UUID().uuidString
        let status = o["status"] as? String ?? "PENDING"
        let price: Double = {
            if let d = o["offerPrice"] as? Double { return d }
            if let n = o["offerPrice"] as? NSNumber { return n.doubleValue }
            if let d = o["offer_price"] as? Double { return d }
            return 0
        }()
        let createdAt: Date? = {
            if let ts = o["createdAt"] as? TimeInterval { return Date(timeIntervalSince1970: ts) }
            if let ts = o["created_at"] as? Double { return Date(timeIntervalSince1970: ts) }
            if let n = o["createdAt"] as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
            return nil
        }()
        // Backend sends senderUsername/sender_username in nested offer for counter attribution; prefer over buyer (buyer stays original purchaser).
        let senderFromOffer = (o["senderUsername"] as? String) ?? (o["sender_username"] as? String)
        let rawBuyerAccount = parseOfferUser(o["buyer"] as? [String: Any])
        let financialBuyerUsername: String? = {
            let t = rawBuyerAccount?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }()
        let buyer: OfferInfo.OfferUser? = {
            if let s = senderFromOffer, !s.trimmingCharacters(in: .whitespaces).isEmpty {
                return OfferInfo.OfferUser(username: s, profilePictureUrl: rawBuyerAccount?.profilePictureUrl)
            }
            return rawBuyerAccount
        }()
        let products = (o["products"] as? [[String: Any]])?.compactMap { parseOfferProduct($0) }
        let updatedBy = (o["updatedBy"] as? String) ?? (o["updated_by"] as? String)
        return OfferInfo(id: id, backendId: id, status: status, offerPrice: price, buyer: buyer, products: products, createdAt: createdAt ?? Date(), sentByCurrentUser: false, financialBuyerUsername: financialBuyerUsername, updatedByUsername: updatedBy)
    }

    private func parseOfferUser(_ j: [String: Any]?) -> OfferInfo.OfferUser? {
        guard let j = j else { return nil }
        return OfferInfo.OfferUser(
            username: j["username"] as? String,
            profilePictureUrl: j["profilePictureUrl"] as? String ?? j["profile_picture_url"] as? String
        )
    }

    private func parseOfferProduct(_ j: [String: Any]) -> OfferInfo.OfferProduct? {
        let id = (j["id"] as? Int).map { String($0) } ?? j["id"] as? String
        return OfferInfo.OfferProduct(
            id: id,
            name: j["name"] as? String,
            seller: parseOfferUser(j["seller"] as? [String: Any])
        )
    }
}
