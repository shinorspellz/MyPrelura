import Foundation

/// Offer data from createOffer response or conversations query. Used for offer card in chat.
/// `id` is a stable UI identity (never mutated). `backendId` is the server offer id when known.
struct OfferInfo: Codable, Hashable {
    /// Stable UI ID (never change after creation).
    let id: String
    /// Backend offer id when known; used for API calls and dedup.
    let backendId: String?
    let status: String?
    let offerPrice: Double
    let buyer: OfferUser?
    /// Account buyer from GraphQL `buyer.username` (marketplace buyer). Differs from `buyer.username` when that field holds `createdBy` for "who sent this row".
    let financialBuyerUsername: String?
    let products: [OfferProduct]?
    /// When the offer was sent; used for card timestamp. Set locally when not from server.
    let createdAt: Date?
    /// When true, this offer was sent by the current user. Always set — never guess from buyer.
    let sentByCurrentUser: Bool
    /// Username of the user who last changed offer status (e.g. who accepted); from GraphQL `updatedBy`.
    let updatedByUsername: String?

    struct OfferUser: Codable, Hashable {
        let username: String?
        let profilePictureUrl: String?
    }

    struct OfferProduct: Codable, Hashable {
        let id: String?
        let name: String?
        let seller: OfferUser?
    }

    enum CodingKeys: String, CodingKey {
        case id, backendId, status, offerPrice, buyer, financialBuyerUsername, products, createdAt, sentByCurrentUser, updatedByUsername
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let idStr = try? c.decode(String.self, forKey: .id) {
            id = idStr
        } else {
            let idAny = try c.decode(AnyCodable.self, forKey: .id)
            id = idAny.value as? String ?? String(describing: idAny.value)
        }
        backendId = try c.decodeIfPresent(String.self, forKey: .backendId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        if let decimal = try? c.decodeIfPresent(Decimal.self, forKey: .offerPrice) {
            offerPrice = NSDecimalNumber(decimal: decimal).doubleValue
        } else if let double = try? c.decodeIfPresent(Double.self, forKey: .offerPrice) {
            offerPrice = double
        } else {
            offerPrice = 0
        }
        buyer = try c.decodeIfPresent(OfferUser.self, forKey: .buyer)
        financialBuyerUsername = try c.decodeIfPresent(String.self, forKey: .financialBuyerUsername)
        products = try c.decodeIfPresent([OfferProduct].self, forKey: .products)
        if let interval = try? c.decodeIfPresent(Double.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: interval)
        } else         if let interval = try? c.decodeIfPresent(TimeInterval.self, forKey: .createdAt) {
            createdAt = Date(timeIntervalSince1970: interval)
        } else {
            createdAt = nil
        }
        sentByCurrentUser = try c.decodeIfPresent(Bool.self, forKey: .sentByCurrentUser) ?? false
        updatedByUsername = try c.decodeIfPresent(String.self, forKey: .updatedByUsername)
    }

    init(id: String, backendId: String? = nil, status: String?, offerPrice: Double, buyer: OfferUser?, products: [OfferProduct]?, createdAt: Date? = nil, sentByCurrentUser: Bool, financialBuyerUsername: String? = nil, updatedByUsername: String? = nil) {
        self.id = id
        self.backendId = backendId
        self.status = status
        self.offerPrice = offerPrice
        self.buyer = buyer
        self.financialBuyerUsername = financialBuyerUsername
        self.products = products
        self.createdAt = createdAt
        self.sentByCurrentUser = sentByCurrentUser
        self.updatedByUsername = updatedByUsername
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(backendId, forKey: .backendId)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(offerPrice, forKey: .offerPrice)
        try c.encodeIfPresent(buyer, forKey: .buyer)
        try c.encodeIfPresent(financialBuyerUsername, forKey: .financialBuyerUsername)
        try c.encodeIfPresent(products, forKey: .products)
        try c.encodeIfPresent(createdAt?.timeIntervalSince1970, forKey: .createdAt)
        try c.encode(sentByCurrentUser, forKey: .sentByCurrentUser)
        try c.encodeIfPresent(updatedByUsername, forKey: .updatedByUsername)
    }

    /// Backend id for API calls (e.g. respondToOffer).
    var offerIdInt: Int? { Int(backendId ?? id) }
    var isPending: Bool { (status ?? "").uppercased() == "PENDING" }
    var isAccepted: Bool { (status ?? "").uppercased() == "ACCEPTED" }
    var isRejected: Bool { (status ?? "").uppercased() == "REJECTED" || (status ?? "").uppercased() == "CANCELLED" }
}
