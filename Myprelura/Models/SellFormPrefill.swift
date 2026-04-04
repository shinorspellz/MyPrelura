import Foundation

/// One-shot payload to fill the sell/upload form (no images). Set on `TabCoordinator` then cleared when Sell applies it.
struct SellFormPrefill: Equatable {
    var title: String
    var description: String
    var category: SellCategory?
    var brand: String?
    var condition: String?
    var colours: [String]
    var sizeId: Int?
    var sizeName: String?
    var measurements: String?
    var material: String?
    var styles: [String]
    var price: Double?
    var discountPrice: Double?
    var parcelSize: String?

    /// Build from a product detail `Item` (list price + optional sale price from originalPrice).
    static func from(item: Item) -> SellFormPrefill {
        let listPrice = item.originalPrice ?? item.price
        let sale: Double? = {
            guard let o = item.originalPrice, o > item.price else { return nil }
            return item.price
        }()
        let category: SellCategory? = {
            guard let id = item.sellCategoryBackendId?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty else {
                return nil
            }
            let name = (item.categoryName ?? item.category.name).trimmingCharacters(in: .whitespacesAndNewlines)
            return SellCategory(id: id, name: name.isEmpty ? "Category" : name, pathNames: [name], pathIds: [id], fullPath: nil)
        }()
        let sizeNm = item.size?.trimmingCharacters(in: .whitespacesAndNewlines)
        let sizeName: String? = {
            guard let s = sizeNm, !s.isEmpty, s.caseInsensitiveCompare("One Size") != .orderedSame else { return nil }
            return s
        }()
        return SellFormPrefill(
            title: item.title,
            description: item.description,
            category: category,
            brand: item.brand,
            condition: Item.conditionKeyForSellForm(from: item.condition),
            colours: item.colors,
            sizeId: item.sellSizeBackendId,
            sizeName: sizeName,
            measurements: nil,
            material: nil,
            styles: [],
            price: listPrice > 0 ? listPrice : nil,
            discountPrice: sale,
            parcelSize: nil
        )
    }
}

extension Item {
    /// Maps API or human-readable condition to sell-form enum keys.
    static func conditionKeyForSellForm(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let u = trimmed.uppercased().replacingOccurrences(of: " ", with: "_")
        let keys = ["BRAND_NEW_WITH_TAGS", "BRAND_NEW_WITHOUT_TAGS", "EXCELLENT_CONDITION", "GOOD_CONDITION", "HEAVILY_USED"]
        if keys.contains(u) { return u }
        let displayToKey: [String: String] = [
            "Brand New With Tags": "BRAND_NEW_WITH_TAGS",
            "Brand new Without Tags": "BRAND_NEW_WITHOUT_TAGS",
            "Excellent Condition": "EXCELLENT_CONDITION",
            "Good Condition": "GOOD_CONDITION",
            "Heavily Used": "HEAVILY_USED",
            "Like New": "EXCELLENT_CONDITION",
            "Excellent": "EXCELLENT_CONDITION",
            "Very Good": "GOOD_CONDITION",
            "Good": "GOOD_CONDITION"
        ]
        if let k = displayToKey[trimmed] { return k }
        return displayToKey.first { trimmed.caseInsensitiveCompare($0.key) == .orderedSame }?.value
    }
}
