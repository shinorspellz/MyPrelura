import Foundation

extension Item {
    /// Maps admin product browse data into a consumer `Item` for native `ItemDetailView` (avoids blank in-app web views on the public site).
    static func fromStaffProductBrowse(_ row: ProductBrowseRow) -> Item {
        let pid = String(row.id)
        let resolvedImages = row.imagesUrl.compactMap { MediaURL.resolvedURL(from: $0)?.absoluteString }
        let un = row.seller?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let seller = User(
            username: un.isEmpty ? "seller" : un,
            displayName: un.isEmpty ? "Seller" : un
        )
        return Item(
            id: id(fromProductId: pid),
            productId: pid,
            listingCode: row.listingCode,
            title: row.name ?? "Listing \(pid)",
            description: "",
            price: row.price ?? 0,
            imageURLs: resolvedImages,
            listDisplayImageURL: resolvedImages.first,
            category: .clothing,
            seller: seller,
            condition: "UNKNOWN",
            status: row.status ?? "ACTIVE"
        )
    }
}
