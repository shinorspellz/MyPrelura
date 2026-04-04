import Foundation

/// Sold event in the chat timeline. Used for ChatItem.sold and SoldConfirmationCardView.
struct OrderInfo: Identifiable, Hashable, Codable {
    let id: String
    let orderId: String
    let price: Double
    let buyerUsername: String
    let sellerUsername: String
    let createdAt: Date
    /// When false, show a neutral loading state for the sold banner until buyer/seller are known (avoids wrong role copy).
    let rolesConfirmed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, orderId, price, buyerUsername, sellerUsername, createdAt, rolesConfirmed
    }

    init(id: String, orderId: String, price: Double, buyerUsername: String, sellerUsername: String, createdAt: Date, rolesConfirmed: Bool) {
        self.id = id
        self.orderId = orderId
        self.price = price
        self.buyerUsername = buyerUsername
        self.sellerUsername = sellerUsername
        self.createdAt = createdAt
        self.rolesConfirmed = rolesConfirmed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        orderId = try c.decode(String.self, forKey: .orderId)
        price = try c.decode(Double.self, forKey: .price)
        buyerUsername = try c.decode(String.self, forKey: .buyerUsername)
        sellerUsername = try c.decode(String.self, forKey: .sellerUsername)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        rolesConfirmed = try c.decodeIfPresent(Bool.self, forKey: .rolesConfirmed) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(orderId, forKey: .orderId)
        try c.encode(price, forKey: .price)
        try c.encode(buyerUsername, forKey: .buyerUsername)
        try c.encode(sellerUsername, forKey: .sellerUsername)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(rolesConfirmed, forKey: .rolesConfirmed)
    }

    /// Build from conversation order + offer context (buyer/seller from offer).
    static func from(conversationOrder: ConversationOrder, buyerUsername: String?, sellerUsername: String?, rolesConfirmed: Bool = true) -> OrderInfo {
        OrderInfo(
            id: "sold-\(conversationOrder.id)",
            orderId: conversationOrder.id,
            price: conversationOrder.total,
            buyerUsername: buyerUsername ?? "",
            sellerUsername: sellerUsername ?? "",
            createdAt: conversationOrder.createdAt ?? Date(),
            rolesConfirmed: rolesConfirmed
        )
    }
}
