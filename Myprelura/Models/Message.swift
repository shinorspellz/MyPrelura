import Foundation

struct Message: Identifiable {
    let id: UUID
    /// Backend message ID (for mark-as-read API).
    let backendId: Int?
    let senderUsername: String
    let content: String
    let preview: String
    let timestamp: Date
    let type: String
    let orderID: String?
    let thumbnailURL: String?
    /// From backend: for **messages you sent**, true once the other participant has opened the thread and marked messages read.
    let read: Bool

    init(
        id: UUID = UUID(),
        backendId: Int? = nil,
        senderUsername: String,
        content: String,
        timestamp: Date = Date(),
        type: String = "order_issue",
        orderID: String? = nil,
        thumbnailURL: String? = nil,
        read: Bool = false
    ) {
        self.id = id
        self.backendId = backendId
        self.senderUsername = senderUsername
        self.content = content
        self.preview = Self.makeListPreview(from: content)
        self.timestamp = timestamp
        self.type = type
        self.orderID = orderID
        self.thumbnailURL = thumbnailURL
        self.read = read
    }

    /// Same `id` for a server row whether the message came from GraphQL or the chat WebSocket (numeric PK is not a valid UUID string).
    static func stableUUID(forBackendId backendId: Int) -> UUID {
        let u = UInt64(bitPattern: Int64(backendId))
        let hex = String(format: "%032llx", u)
        let uuid = "\(hex.prefix(8))-\(hex.dropFirst(8).prefix(4))-\(hex.dropFirst(12).prefix(4))-\(hex.dropFirst(16).prefix(4))-\(hex.dropFirst(20).prefix(12))"
        return UUID(uuidString: String(uuid)) ?? UUID()
    }

    /// Plain-text / emoji-only messages: scale for 1–4 emoji (5×…2×); 5+ emoji use 1×. Nil if not emoji-only (e.g. JSON or mixed text).
    var emojiOnlyScaleMultiplier: Double? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("{") else { return nil }
        // ASCII letters/digits only (e.g. test codes like "90768798") must use the standard bubble, not emoji-only styling (no background).
        if trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
            return nil
        }
        var emojiCount = 0
        for ch in trimmed where !ch.isWhitespace {
            guard ch.isEmojiForChatBubble else { return nil }
            emojiCount += 1
        }
        guard emojiCount > 0 else { return nil }
        switch emojiCount {
        case 1: return 5
        case 2: return 4
        case 3: return 3
        case 4: return 2
        default: return 1
        }
    }
    
    /// One-line preview for inbox/lists; never surface raw JSON for structured message types.
    private static func makeListPreview(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let type = json["type"] as? String {
            switch type {
            case "order_issue": return "Issue reported"
            case "order": return "Order update"
            case "offer": return "Offer"
            case "sold_confirmation": return "Order confirmed"
            case "order_cancellation_request": return "Cancellation requested"
            case "order_cancellation_outcome":
                let approved = (json["approved"] as? Bool) ?? false
                return approved ? "Order cancellation was approved" : "Order cancellation was declined"
            case "account_report": return humanReadableReportLine(json: json, reportType: type, maxLength: 56)
            case "product_report": return humanReadableReportLine(json: json, reportType: type, maxLength: 56)
            default: break
            }
        }
        return String(content.prefix(50)) + "..."
    }

    /// `reason` first, then `description`; truncates for list rows. Used by chat inbox preview too.
    static func humanReadableReportLine(json: [String: Any], reportType: String, maxLength: Int) -> String {
        let label = reportType == "account_report" ? "Account report" : "Product report"
        let rawDetail = (json["reason"] as? String) ?? (json["description"] as? String)
        let detail = rawDetail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ") ?? ""
        guard !detail.isEmpty else { return label }
        let full = "\(label): \(detail)"
        guard full.count > maxLength else { return full }
        guard maxLength > 2 else { return "…" }
        return String(full.prefix(maxLength - 1)) + "…"
    }

    var formattedTimestamp: String {
        let now = Date()
        let interval = timestamp.timeIntervalSince(now)
        if interval > -60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let str = formatter.localizedString(for: timestamp, relativeTo: now)
        if str.hasPrefix("in ") {
            return "Just now"
        }
        return str
    }

    /// True when content is offer payload (JSON type "offer" or backend sending Python-style e.g. {'offer_id': 323}).
    var isOfferContent: Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["type"] as? String == "offer" { return true }
            if json["offer_id"] != nil || json["offerId"] != nil { return true }
        }
        // Avoid `contains("offer_id")`: normal URLs (e.g. ?offer_id=) hid peer text in offer threads via `displayedMessages`.
        if trimmed.contains("\"offer_id\"") || trimmed.contains("'offer_id'") { return true }
        return false
    }

    /// Parsed offer id and price from message content (for building offer history from messages). Returns nil if not offer content or unparseable.
    /// Supports offer_id / offerId and offerPrice / offer_price so all offer messages show in history.
    var parsedOfferDetails: (offerId: String, offerPrice: Double)? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let hasOffer = json["type"] as? String == "offer" || json["offer_id"] != nil || json["offerId"] != nil
        guard hasOffer else { return nil }
        let offerId: String?
        if let id = json["offer_id"] as? Int { offerId = String(id) }
        else if let id = json["offer_id"] as? String { offerId = id }
        else if let id = json["offerId"] as? Int { offerId = String(id) }
        else if let id = json["offerId"] as? String { offerId = id }
        else { offerId = nil }
        guard let id = offerId else { return nil }
        var offerPrice: Double = 0
        if let p = json["offerPrice"] as? Double { offerPrice = p }
        else if let p = json["offer_price"] as? Double { offerPrice = p }
        else if let n = json["offerPrice"] as? NSNumber { offerPrice = n.doubleValue }
        else if let n = json["offer_price"] as? NSNumber { offerPrice = n.doubleValue }
        return (id, offerPrice)
    }

    /// Human-readable text for bubbles: show "You reported an issue" / "Order update" / "Offer sent"|"New offer" for JSON or offer payload, else plain content.
    /// Pass isFromCurrentUser so we show "Offer sent" for sender and "New offer" for recipient.
    func displayContentForBubble(isFromCurrentUser: Bool) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = json["type"] as? String {
            switch type {
            case "order_issue":
                if isFromCurrentUser { return "You reported an issue" }
                let u = senderUsername.trimmingCharacters(in: .whitespacesAndNewlines)
                return u.isEmpty ? "Issue reported" : "\(senderUsername) reported an issue"
            case "order": return "Order update"
            case "offer": return isFromCurrentUser ? "Offer sent" : "New offer"
            case "sold_confirmation": return "Order confirmed"
            case "order_cancellation_request": return isFromCurrentUser ? "You requested cancellation" : "Cancellation requested"
            case "order_cancellation_outcome":
                let approved = (json["approved"] as? Bool) ?? false
                return approved ? "Order cancellation was approved" : "Order cancellation was declined"
            case "account_report": return Self.humanReadableReportLine(json: json, reportType: type, maxLength: 280)
            case "product_report": return Self.humanReadableReportLine(json: json, reportType: type, maxLength: 280)
            default: break
            }
        }
        if isOfferContent {
            return isFromCurrentUser ? "Offer sent" : "New offer"
        }
        return content
    }

    /// Human-readable text for list preview; does not need sender context.
    var displayContent: String {
        displayContentForBubble(isFromCurrentUser: false)
    }

    /// True when backend sent itemType "sold_confirmation" or content is JSON with type "sold_confirmation" (show as "Order confirmed" bubble; sale UI is OrderConfirmationCardView).
    var isSoldConfirmation: Bool {
        if type == "sold_confirmation" { return true }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["type"] as? String else { return false }
        return t == "sold_confirmation"
    }

    /// Backend `sold_confirmation` JSON (`order_offer_chat.add_sold_confirmation_message`): order_id, buyer_subtotal, etc.
    var parsedSoldConfirmationPayload: (orderId: String, price: Double)? {
        guard isSoldConfirmation else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "sold_confirmation" else { return nil }
        guard let oidRaw = json["order_id"] else { return nil }
        let orderId: String? = {
            if let n = oidRaw as? Int { return String(n) }
            if let n = oidRaw as? NSNumber { return n.stringValue }
            if let s = oidRaw as? String, !s.isEmpty { return s }
            return nil
        }()
        guard let orderId else { return nil }
        let price: Double = {
            if let s = json["buyer_subtotal"] as? String { return Double(s) ?? 0 }
            if let n = json["buyer_subtotal"] as? Double { return n }
            if let n = json["buyer_subtotal"] as? Int { return Double(n) }
            if let s = json["product_price"] as? String { return Double(s) ?? 0 }
            if let n = json["product_price"] as? Double { return n }
            return 0
        }()
        return (orderId, price)
    }

    var isOrderIssue: Bool {
        if type == "order_issue" { return true }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["type"] as? String else { return false }
        return t == "order_issue"
    }

    /// Parse order issue payload persisted in chat message text.
    /// Backend payload keys observed: order_id, issue_id, public_id, issue_type, description, images_url/imagesUrl.
    var parsedOrderIssueDetails: (orderId: String?, issueId: Int?, publicId: String?, issueType: String?, description: String?, imageUrls: [String])? {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "order_issue" || type == "order_issue" else { return nil }

        let orderId: String? = {
            if let n = json["order_id"] as? Int { return String(n) }
            if let s = json["order_id"] as? String { return s }
            if let n = json["orderId"] as? Int { return String(n) }
            if let s = json["orderId"] as? String { return s }
            return nil
        }()
        let issueId: Int? = {
            if let n = json["issue_id"] as? Int { return n }
            if let s = json["issue_id"] as? String { return Int(s) }
            if let n = json["issueId"] as? Int { return n }
            if let s = json["issueId"] as? String { return Int(s) }
            return nil
        }()
        let publicId: String? = {
            if let s = json["public_id"] as? String { return s }
            if let s = json["publicId"] as? String { return s }
            return nil
        }()
        let issueType: String? = {
            if let s = json["issue_type"] as? String { return s }
            if let s = json["issueType"] as? String { return s }
            return nil
        }()
        let description: String? = {
            if let s = json["description"] as? String { return s }
            if let s = json["details"] as? String { return s }
            if let s = json["message"] as? String { return s }
            return nil
        }()
        let imageUrls: [String] = {
            let raw = (json["images_url"] as? [String])
                ?? (json["imagesUrl"] as? [String])
                ?? (json["images"] as? [String])
                ?? []
            return raw.compactMap { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                if trimmed.hasPrefix("{"),
                   let data = trimmed.data(using: .utf8),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let url = obj["url"] as? String {
                    return url
                }
                return trimmed
            }
        }()
        return (orderId, issueId, publicId, issueType, description, imageUrls)
    }

    var isOrderCancellationRequest: Bool {
        if type == "order_cancellation_request" { return true }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["type"] as? String else { return false }
        return t == "order_cancellation_request"
    }

    /// Backend `order_cancellation_request` JSON from order_offer_chat.
    var parsedOrderCancellationRequestPayload: (orderId: Int, requestedBySeller: Bool, status: String)? {
        guard isOrderCancellationRequest else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "order_cancellation_request" else { return nil }
        let oid: Int? = {
            if let n = json["order_id"] as? Int { return n }
            if let s = json["order_id"] as? String { return Int(s) }
            if let n = json["orderId"] as? Int { return n }
            if let s = json["orderId"] as? String { return Int(s) }
            return nil
        }()
        guard let orderId = oid else { return nil }
        let requested = (json["requested_by_seller"] as? Bool) ?? (json["requestedBySeller"] as? Bool) ?? false
        let st = (json["status"] as? String) ?? "PENDING"
        return (orderId, requested, st)
    }

    /// Follow-up row when counterparty approves or rejects (`order_cancellation_outcome` JSON).
    var parsedOrderCancellationOutcomePayload: (orderId: Int, approved: Bool)? {
        guard isOrderCancellationOutcome else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "order_cancellation_outcome" else { return nil }
        let oid: Int? = {
            if let n = json["order_id"] as? Int { return n }
            if let s = json["order_id"] as? String { return Int(s) }
            if let n = json["orderId"] as? Int { return n }
            if let s = json["orderId"] as? String { return Int(s) }
            return nil
        }()
        guard let orderId = oid else { return nil }
        let approved = (json["approved"] as? Bool) ?? false
        return (orderId, approved)
    }

    var isOrderCancellationOutcome: Bool {
        if type == "order_cancellation_outcome" { return true }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let t = json["type"] as? String else { return false }
        return t == "order_cancellation_outcome"
    }
}

extension Message: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, backendId, senderUsername, content, timestamp, type, orderID, thumbnailURL, read
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        backendId = try c.decodeIfPresent(Int.self, forKey: .backendId)
        senderUsername = try c.decode(String.self, forKey: .senderUsername)
        content = try c.decode(String.self, forKey: .content)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "order_issue"
        orderID = try c.decodeIfPresent(String.self, forKey: .orderID)
        thumbnailURL = try c.decodeIfPresent(String.self, forKey: .thumbnailURL)
        read = try c.decodeIfPresent(Bool.self, forKey: .read) ?? false
        preview = Self.makeListPreview(from: content)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(backendId, forKey: .backendId)
        try c.encode(senderUsername, forKey: .senderUsername)
        try c.encode(content, forKey: .content)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(orderID, forKey: .orderID)
        try c.encodeIfPresent(thumbnailURL, forKey: .thumbnailURL)
        try c.encode(read, forKey: .read)
    }
}

extension Message {
    static let sampleMessages: [Message] = [
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123456"}"#,
            timestamp: Date().addingTimeInterval(-6 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/miniskirt1/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123457"}"#,
            timestamp: Date().addingTimeInterval(-8 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/halter1/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123458"}"#,
            timestamp: Date().addingTimeInterval(-9 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/sequin1/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123459"}"#,
            timestamp: Date().addingTimeInterval(-12 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/skirt2/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123460"}"#,
            timestamp: Date().addingTimeInterval(-46 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/leopard1/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123461"}"#,
            timestamp: Date().addingTimeInterval(-48 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/stripe1/200/200"
        ),
        Message(
            senderUsername: "shinor",
            content: #"{"type": "order_issue", "order_id": "is123462"}"#,
            timestamp: Date().addingTimeInterval(-48 * 24 * 60 * 60),
            thumbnailURL: "https://picsum.photos/seed/strapless1/200/200"
        )
    ]
}

private extension Character {
    var isEmojiForChatBubble: Bool {
        let scalars = unicodeScalars
        let allowed = scalars.allSatisfy { s in
            s.properties.isEmoji
                || s.properties.isEmojiModifier
                || s.value == 0x200D
                || s.value == 0xFE0F
                || s.properties.isVariationSelector
        }
        guard allowed else { return false }
        return scalars.contains { $0.properties.isEmoji }
    }
}
