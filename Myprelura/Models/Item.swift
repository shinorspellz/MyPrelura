import Foundation

struct Item: Identifiable, Hashable {
    let id: UUID
    let productId: String? // Store the actual backend product ID
    /// Public listing code for `/item/{slug}` URLs (preferred over numeric id when sharing).
    let listingCode: String?
    let title: String
    let description: String
    let price: Double
    let originalPrice: Double? // For discount calculations
    let imageURLs: [String]
    /// Prefer for inbox/chat thumbnails when API JSON includes `thumbnail` (smaller than full `url`).
    let listDisplayImageURL: String?
    let category: Category
    let categoryName: String? // Store the actual category name from API (subcategory)
    let seller: User
    let condition: String
    let size: String?
    let brand: String?
    /// Product color names from API (e.g. ["Blue", "Navy"]); used for colour integration on detail.
    let colors: [String]
    let likeCount: Int
    let views: Int
    let createdAt: Date
    let isLiked: Bool
    /// Product status from API (e.g. "ACTIVE", "SOLD"). Used to hide Buy/Offer for sold items and filter marketplace.
    let status: String
    /// GraphQL category id when available (sell prefill).
    let sellCategoryBackendId: String?
    /// GraphQL product size id when available (sell prefill).
    let sellSizeBackendId: Int?
    
    init(
        id: UUID = UUID(),
        productId: String? = nil,
        listingCode: String? = nil,
        title: String,
        description: String,
        price: Double,
        originalPrice: Double? = nil,
        imageURLs: [String],
        listDisplayImageURL: String? = nil,
        category: Category,
        categoryName: String? = nil,
        seller: User,
        condition: String,
        size: String? = nil,
        brand: String? = nil,
        colors: [String] = [],
        likeCount: Int = 0,
        views: Int = 0,
        createdAt: Date = Date(),
        isLiked: Bool = false,
        status: String = "ACTIVE",
        sellCategoryBackendId: String? = nil,
        sellSizeBackendId: Int? = nil
    ) {
        self.id = id
        self.productId = productId
        self.listingCode = listingCode
        self.title = title
        self.description = description
        self.price = price
        self.originalPrice = originalPrice
        self.imageURLs = imageURLs
        self.listDisplayImageURL = listDisplayImageURL
        self.category = category
        self.categoryName = categoryName
        self.seller = seller
        self.condition = condition
        self.size = size
        self.brand = brand
        self.colors = colors
        self.likeCount = likeCount
        self.views = views
        self.createdAt = createdAt
        self.isLiked = isLiked
        self.status = status
        self.sellCategoryBackendId = sellCategoryBackendId
        self.sellSizeBackendId = sellSizeBackendId
    }
    
    // Hashable conformance
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: Item, rhs: Item) -> Bool {
        lhs.id == rhs.id
    }

    /// Deterministic UUID from backend product id so the same product always has the same id (avoids wrong product opening in grids/navigation).
    static func id(fromProductId productId: String) -> UUID {
        guard let intVal = Int(productId), intVal >= 0 else { return UUID() }
        let hex = String(format: "%012llx", UInt64(intVal))
        let uuidString = "00000000-0000-0000-0000-\(hex)"
        return UUID(uuidString: uuidString) ?? UUID()
    }
    
    /// Returns a copy with updated like state (for optimistic/local updates after toggle like).
    func with(likeCount: Int? = nil, isLiked: Bool? = nil, status: String? = nil, listingCode: String? = nil) -> Item {
        Item(
            id: id,
            productId: productId,
            listingCode: listingCode ?? self.listingCode,
            title: title,
            description: description,
            price: price,
            originalPrice: originalPrice,
            imageURLs: imageURLs,
            listDisplayImageURL: listDisplayImageURL,
            category: category,
            categoryName: categoryName,
            seller: seller,
            condition: condition,
            size: size,
            brand: brand,
            colors: self.colors,
            likeCount: likeCount ?? self.likeCount,
            views: views,
            createdAt: createdAt,
            isLiked: isLiked ?? self.isLiked,
            status: status ?? self.status,
            sellCategoryBackendId: sellCategoryBackendId,
            sellSizeBackendId: sellSizeBackendId
        )
    }

    /// Format price: whole numbers as "£14", decimals as "£6.80" or "£6.87"
    private static func formatPrice(_ value: Double) -> String {
        CurrencyFormatter.gbp(value)
    }
    
    var formattedPrice: String {
        Self.formatPrice(price)
    }

    /// First image URL for small UI chrome (message list, chat headers): uses list thumbnail when available.
    var thumbnailURLForChrome: String? {
        if let s = listDisplayImageURL?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        guard let u = imageURLs.first?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty else { return nil }
        return u
    }
    
    var formattedOriginalPrice: String {
        guard let originalPrice = originalPrice else { return "" }
        return Self.formatPrice(originalPrice)
    }
    
    var discountPercentage: Int? {
        guard let originalPrice = originalPrice, originalPrice > price else { return nil }
        return Int(((originalPrice - price) / originalPrice) * 100)
    }
    
    /// True when product status is SOLD (hide Buy/Offer, show sold state).
    var isSold: Bool { status.uppercased() == "SOLD" }

    /// Path segment for universal links and sharing (`/item/{slug}`).
    var publicWebItemSlug: String {
        let lc = listingCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !lc.isEmpty { return lc }
        return productId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    var formattedCondition: String {
        // Map condition enum values to display text (matching Flutter app)
        switch condition.uppercased() {
        case "BRAND_NEW_WITH_TAGS":
            return "Brand New With Tags"
        case "BRAND_NEW_WITHOUT_TAGS":
            return "Brand new Without Tags"
        case "EXCELLENT_CONDITION":
            return "Excellent Condition"
        case "GOOD_CONDITION":
            return "Good Condition"
        case "HEAVILY_USED":
            return "Heavily Used"
        default:
            // If already formatted or unknown, return as-is
            return condition
        }
    }
}

extension Array where Element == Item {
    /// Returns a new array with the item matching productId replaced by the given item.
    func replacingItem(productId: String, with updated: Item) -> [Item] {
        map { $0.productId == productId ? updated : $0 }
    }
    /// Excludes items from sellers who have vacation mode on (so they are hidden from catalogues).
    func excludingVacationModeSellers() -> [Item] {
        filter { !$0.seller.isVacationMode }
    }
    /// Excludes sold items from marketplace feeds.
    func excludingSold() -> [Item] {
        filter { !$0.isSold }
    }
}

// Sample data
extension Item {
    static let sampleItems: [Item] = [
        Item(
            productId: "1",
            title: "Oakley T-shirt Size Large",
            description: "Vintage Oakley California t-shirt in good condition.",
            price: 12.00,
            imageURLs: ["https://picsum.photos/seed/oakley-tshirt/400/460"],
            category: .clothing,
            seller: User(
                username: "bad_seed_vintage",
                displayName: "Bad Seed Vintage",
                avatarURL: "https://i.pravatar.cc/150?img=12",
                listingsCount: 50,
                followingsCount: 20,
                followersCount: 500
            ),
            condition: "Good Condition",
            size: "L",
            brand: "Oakley",
            likeCount: 0
        ),
        Item(
            productId: "2",
            title: "Ladies Short Dress",
            description: "Beautiful red off-the-shoulder dress.",
            price: 2.00,
            imageURLs: ["https://picsum.photos/seed/red-dress/400/460"],
            category: .clothing,
            seller: User(
                username: "rixy37",
                displayName: "Rixy",
                avatarURL: "https://i.pravatar.cc/150?img=47",
                listingsCount: 30,
                followingsCount: 15,
                followersCount: 300
            ),
            condition: "Brand new Without Tags",
            size: "M",
            brand: "Atmosphere",
            likeCount: 0
        ),
        Item(
            productId: "3",
            title: "Nike Cropped Top",
            description: "Stylish cropped top in excellent condition.",
            price: 65.00,
            originalPrice: 130.00,
            imageURLs: ["https://picsum.photos/seed/nike-cropped/400/460"],
            category: .clothing,
            seller: .sampleUser,
            condition: "Like New",
            size: "M",
            brand: "Nike",
            likeCount: 14
        ),
        Item(
            productId: "4",
            title: "Gucci Bag",
            description: "Beautiful designer handbag with gold hardware. Barely used.",
            price: 650.00,
            imageURLs: ["https://picsum.photos/seed/gucci-bag/400/460"],
            category: .accessories,
            seller: .sampleUser,
            condition: "Like New",
            brand: "Gucci",
            likeCount: 45
        ),
        Item(
            productId: "5",
            title: "Vintage Denim Jacket",
            description: "Classic blue denim jacket in excellent condition. Perfect for layering.",
            price: 45.00,
            imageURLs: ["https://picsum.photos/seed/denim-jacket/400/460"],
            category: .clothing,
            seller: .sampleUser,
            condition: "Excellent",
            size: "M",
            brand: "Levis",
            likeCount: 8
        ),
        Item(
            productId: "6",
            title: "The North Face Jacket",
            description: "Warm and durable outdoor jacket.",
            price: 120.00,
            imageURLs: ["https://picsum.photos/seed/tnf-jacket/400/460"],
            category: .clothing,
            seller: .sampleUser,
            condition: "Very Good",
            size: "L",
            brand: "The North Face",
            likeCount: 22
        )
    ]
    
    static let discoverSampleItems: [Item] = [
        Item(
            productId: "7",
            title: "Zara Black Satin Midi Tw",
            description: "Elegant black satin midi dress with cowl neck.",
            price: 30.00,
            imageURLs: ["https://picsum.photos/seed/zara-dress/400/460"],
            category: .clothing,
            seller: User(
                username: "francescaabb",
                displayName: "Francesca",
                listingsCount: 25,
                followingsCount: 10,
                followersCount: 200
            ),
            condition: "Brand New With Tags",
            size: "M",
            brand: "Zara",
            likeCount: 0
        ),
        Item(
            productId: "8",
            title: "Hope & Ivy Cream & Mul",
            description: "Beautiful cream floral dress with ruffled sleeves.",
            price: 45.00,
            imageURLs: ["https://picsum.photos/seed/hope-ivy/400/460"],
            category: .clothing,
            seller: User(
                username: "second_bloom",
                displayName: "Second Bloom",
                listingsCount: 40,
                followingsCount: 18,
                followersCount: 350
            ),
            condition: "Good Condition",
            size: "S",
            brand: "Hope & Ivy",
            likeCount: 0
        ),
        Item(
            productId: "9",
            title: "Corset Top",
            description: "Leopard print corset top with black lace trim.",
            price: 35.00,
            imageURLs: ["https://picsum.photos/seed/corset-top/400/460"],
            category: .clothing,
            seller: User(
                username: "testuser",
                displayName: "Test User",
                listingsCount: 5,
                followingsCount: 2,
                followersCount: 3
            ),
            condition: "Excellent Condition",
            size: "M",
            brand: "17 Patterns",
            likeCount: 0
        ),
        Item(
            productId: "10",
            title: "Denim Boots",
            description: "Unique denim boots with high heels and decorative details.",
            price: 80.00,
            imageURLs: ["https://picsum.photos/seed/denim-boots/400/460"],
            category: .shoes,
            seller: User(
                username: "testuser",
                displayName: "Test User",
                listingsCount: 5,
                followingsCount: 2,
                followersCount: 3
            ),
            condition: "Good Condition",
            size: "7",
            brand: "032c",
            likeCount: 0
        )
    ]
}
