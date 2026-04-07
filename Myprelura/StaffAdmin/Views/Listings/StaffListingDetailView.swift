import SwiftUI

/// Staff: shopper-style product detail from a `ProductBrowseRow` (share link + flag).
struct StaffListingDetailView: View {
    @EnvironmentObject private var authService: AuthService
    let product: ProductBrowseRow
    let onFlag: () -> Void

    private var item: Item { Item.fromStaffProductBrowse(product) }

    var body: some View {
        ItemDetailView(item: item, authService: authService)
            .background(Theme.Colors.background)
            .adminNavigationChrome()
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if let url = Constants.publicProductURL(productId: product.id, listingCode: product.listingCode) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    Button("Flag") { onFlag() }
                }
            }
    }
}
