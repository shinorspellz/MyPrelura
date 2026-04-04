import Foundation

/// GraphQL `Decimal` / mixed numeric JSON.
struct GQLDecimal: Decodable, Hashable {
    let raw: String

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            raw = s
            return
        }
        if let d = try? c.decode(Double.self) {
            raw = String(d)
            return
        }
        if let i = try? c.decode(Int.self) {
            raw = String(i)
            return
        }
        raw = "0"
    }

    var display: String {
        if let v = Double(raw) {
            return String(format: v.truncatingRemainder(dividingBy: 1) == 0 ? "£%.0f" : "£%.2f", v)
        }
        return "£\(raw)"
    }
}

struct AnalyticsOverviewDTO: Decodable, Hashable {
    let totalProductViews: Int?
    let totalProductViewsToday: Int?
    let totalUsers: Int?
    let totalNewUsersToday: Int?
    let totalUsersPercentageChange: Double?
    let totalProductViewsPercentageChange: Double?
    let totalProductViewsBeforeTodayPercentage: Double?
    let newUsersPercentageChange: Double?
}

struct StaffAdminReportRow: Decodable, Identifiable, Hashable {
    let id: Int
    let publicId: String?
    let reportType: String?
    let reason: String?
    let context: String?
    let imagesUrl: [String]?
    let status: String?
    let dateCreated: String?
    let updatedAt: String?
    let reportedByUsername: String?
    let accountReportedUsername: String?
    let productId: Int?
    let productName: String?
    let supportConversationId: Int?
    let conversationId: Int?
}

struct UserAdminRow: Decodable, Identifiable, Hashable {
    let id: Int
    let username: String?
    let email: String?
    let displayName: String?
    let firstName: String?
    let lastName: String?
    let isVerified: Bool?
    let isStaff: Bool?
    let isSuperuser: Bool?
    let activeListings: Int?
    let totalListings: Int?
    let totalSales: GQLDecimal?
    let totalShopValue: GQLDecimal?
    let thumbnailUrl: String?
    let profilePictureUrl: String?
    let dateJoined: String?
    let lastLogin: String?
    let lastSeen: String?
    let noOfFollowers: Int?
    let noOfFollowing: Int?
    let credit: Int?
}

struct ProductBrowseRow: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String?
    let listingCode: String?
    let status: String?
    /// Normalised listing price (GraphQL `price` may be JSON int or float).
    let price: Double?
    let seller: SellerBrief?
    /// First-party image URLs from `imagesUrl` (may be empty if backend stores non-string shapes).
    let imagesUrl: [String]

    struct SellerBrief: Decodable, Hashable {
        let username: String?
    }

    var primaryImageURL: URL? {
        MediaURL.resolvedURL(from: imagesUrl.first)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, listingCode, status, price, seller, imagesUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = intId
        } else if let s = try? c.decode(String.self, forKey: .id), let intId = Int(s) {
            id = intId
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Expected Int or String id for product.")
        }
        name = try c.decodeIfPresent(String.self, forKey: .name)
        listingCode = try c.decodeIfPresent(String.self, forKey: .listingCode)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        if let d = try? c.decode(Double.self, forKey: .price) {
            price = d
        } else if let i = try? c.decode(Int.self, forKey: .price) {
            price = Double(i)
        } else if let s = try? c.decode(String.self, forKey: .price), let d = Double(s) {
            price = d
        } else {
            price = nil
        }
        seller = try c.decodeIfPresent(SellerBrief.self, forKey: .seller)
        imagesUrl = ProductBrowseRow.decodeImagesUrl(from: c, forKey: .imagesUrl)
    }

    private static func decodeImagesUrl(from c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> [String] {
        if let direct = try? c.decode([String].self, forKey: key) {
            return direct.flatMap { stringsFromImagePayload($0) }
        }
        if let single = try? c.decode(String.self, forKey: key) {
            return stringsFromImagePayload(single)
        }
        guard var nested = try? c.nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [String] = []
        while !nested.isAtEnd {
            if let s = try? nested.decode(String.self) {
                out.append(contentsOf: stringsFromImagePayload(s))
            } else if let dict = try? nested.decode([String: String].self) {
                let keys = [
                    "url", "image", "image_url", "imageUrl", "thumbnail", "thumbnailUrl",
                    "src", "href", "path", "link", "fullUrl",
                ]
                var found: String?
                for k in keys {
                    if let v = dict[k], !v.isEmpty { found = v; break }
                }
                if let found { out.append(found) }
            } else {
                _ = try? nested.decode(AdminDTOsSkippedJSON.self)
            }
        }
        return out
    }

    /// GraphQL sometimes returns each `imagesUrl` entry as a JSON object string (`{"image":"/media/..."}`) or a plain path.
    private static func stringsFromImagePayload(_ s: String) -> [String] {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        if t.hasPrefix("{"), let data = t.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let keys = [
                "url", "image", "imageUrl", "image_url", "thumbnail", "thumbnailUrl",
                "src", "href", "path", "link", "fullUrl",
            ]
            for k in keys {
                if let v = obj[k] as? String, !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return [v]
                }
            }
            return []
        }
        return [t]
    }
}

/// Decodes and discards a single JSON value so we can skip unknown elements in `imagesUrl` arrays.
private struct AdminDTOsSkippedJSON: Decodable {
    init(from decoder: Decoder) throws {
        if let c = try? decoder.singleValueContainer() {
            if c.decodeNil() { return }
            if (try? c.decode(Bool.self)) != nil { return }
            if (try? c.decode(String.self)) != nil { return }
            if (try? c.decode(Double.self)) != nil { return }
            if (try? c.decode(Int.self)) != nil { return }
        }
        _ = try? decoder.container(keyedBy: GenericCodingKey.self)
        _ = try? decoder.unkeyedContainer()
    }

    private struct GenericCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { stringValue = "\(intValue)"; self.intValue = intValue }
    }
}

struct AdminOrderRow: Decodable, Identifiable, Hashable {
    let id: String
    let priceTotal: GQLDecimal
    let status: String?
    let createdAt: String?
    let user: BuyerBrief?

    struct BuyerBrief: Decodable, Hashable {
        let username: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let intId = try? c.decode(Int.self, forKey: .id) {
            id = String(intId)
        } else {
            id = try c.decode(String.self, forKey: .id)
        }
        priceTotal = try c.decode(GQLDecimal.self, forKey: .priceTotal)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        user = try c.decodeIfPresent(BuyerBrief.self, forKey: .user)
    }

    private enum CodingKeys: String, CodingKey {
        case id, priceTotal, status, createdAt, user
    }
}

struct BannerRow: Decodable, Identifiable, Hashable {
    let id: Int
    let title: String?
    let season: String?
    let isActive: Bool?
    let bannerUrl: [String]?
}

struct ViewMeDTO: Decodable {
    let id: Int?
    let username: String?
    let email: String?
    let isStaff: Bool?
    let isSuperuser: Bool?
}

struct UserProfileDTO: Decodable {
    let id: Int?
    let username: String?
    let email: String?
    let firstName: String?
    let lastName: String?
    let displayName: String?
    let bio: String?
    let isVerified: Bool?
    let listing: Int?
    let dateJoined: String?
    let lastLogin: String?
    let lastSeen: String?
    let thumbnailUrl: String?
    let profilePictureUrl: String?
    let noOfFollowers: Int?
    let noOfFollowing: Int?
    let credit: Int?
    let reviewStats: ReviewStatsDTO?

    struct ReviewStatsDTO: Decodable {
        let noOfReviews: Int?
        let rating: Double?
    }
}

struct ChatMessageDTO: Decodable, Identifiable, Hashable {
    let id: Int
    let text: String?
    let createdAt: String?
    let sender: SenderBrief?

    struct SenderBrief: Decodable, Hashable {
        let username: String?
    }
}

enum StaffAccessLevel: String, CaseIterable {
    case staff = "Staff"
    case admin = "Admin"

    var canDeleteUsers: Bool { self == .admin }
    /// Product flag is allowed for staff in the backend; we still show the action to both roles.
    var canModerateListings: Bool { true }
}
