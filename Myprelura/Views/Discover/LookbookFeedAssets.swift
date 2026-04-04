import Foundation
import UIKit

/// Bundled JPEGs in `Prelura-swift/LookbookFeed/` (copied from the designer folder). Loaded by resource name without extension.
enum LookbookFeedAssets {
    static let bundleSubdirectory = "LookbookFeed"
    static let bannerResourceName = "lookbook_banner_main"
    private static let casualStyleResource = "lookbook_style_casual"

    /// Subjective split so non-`CASUAL` slots alternate for visual balance (not biometric data).
    private static let menStylePool = ["lb_pool_01", "lb_pool_03", "lb_pool_04", "lb_pool_06", "lb_pool_08", "lb_pool_10"]
    private static let womenStylePool = ["lb_pool_02", "lb_pool_05", "lb_pool_07", "lb_pool_09", "lb_pool_11"]

    /// `lookbookStylePillValues` index 0 → casual image; remaining indices cycle men/women pools (may repeat images).
    static func styleThumbnailResource(styleIndex: Int) -> String {
        guard styleIndex > 0 else { return casualStyleResource }
        if styleIndex % 2 == 1 {
            return womenStylePool[(styleIndex / 2) % womenStylePool.count]
        }
        return menStylePool[((styleIndex / 2) - 1 + menStylePool.count) % menStylePool.count]
    }

    /// Four cards; disjoint filenames from **Get inspired** (no image used twice across the two rows).
    /// `styleFilter` drives the topic lookbook feed (posts tagged with any of these styles).
    static let exploreCommunityCards: [LookbookHorizontalCard] = [
        LookbookHorizontalCard(resourceName: "lb_pool_01", overlayTitle: "Curated sellers", styleFilter: ["CHIC"]),
        LookbookHorizontalCard(resourceName: "lb_pool_03", overlayTitle: "Street scene", styleFilter: ["STREETWEAR"]),
        LookbookHorizontalCard(resourceName: "lb_pool_05", overlayTitle: "Daily wear", styleFilter: ["CASUAL"]),
        LookbookHorizontalCard(resourceName: "lb_pool_07", overlayTitle: "Studio fits", styleFilter: ["MINIMALIST"])
    ]

    static let getInspiredCards: [LookbookHorizontalCard] = [
        LookbookHorizontalCard(resourceName: "lb_pool_02", overlayTitle: "Editor's picks", styleFilter: ["VINTAGE"]),
        LookbookHorizontalCard(resourceName: "lb_pool_04", overlayTitle: "This week", styleFilter: ["Y2K"]),
        LookbookHorizontalCard(resourceName: "lb_pool_06", overlayTitle: "Mood board", styleFilter: ["PARTY_DRESS"]),
        LookbookHorizontalCard(resourceName: "lb_pool_08", overlayTitle: "Fresh angles", styleFilter: ["ACTIVEWEAR"])
    ]

    static func imageURL(named name: String) -> URL? {
        let b = Bundle.main
        if let u = b.url(forResource: name, withExtension: "jpg", subdirectory: bundleSubdirectory) { return u }
        return b.url(forResource: name, withExtension: "jpg")
    }

    static func uiImage(named name: String) -> UIImage? {
        guard let u = imageURL(named: name) else { return nil }
        return UIImage(contentsOfFile: u.path)
    }
}

struct LookbookHorizontalCard: Hashable, Identifiable {
    var id: String { resourceName }
    let resourceName: String
    let overlayTitle: String
    let styleFilter: Set<String>
}
