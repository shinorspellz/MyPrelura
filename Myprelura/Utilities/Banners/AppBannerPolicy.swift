import Foundation

/// Identifiers for **modal intros**, **coach marks**, and future **home banners** so presentation rules stay in one place.
enum AppBannerID: String, CaseIterable {
    /// Full-screen Try Cart story when opening Shop All (`FilteredProductsView` + `.tryCartSearch`).
    case tryCartShopAllIntro
}

/// Rules for when to show in-app banners and full-screen intros. Flip flags here when moving from QA to production.
enum AppBannerPolicy {
    private static let defaults = UserDefaults.standard
    private static let seenKeyPrefix = "app_banner_seen_"

    // MARK: - Tunables

    /// `true`: Shop All Try Cart intro shows on **every** entry to Shop All (each navigation push).  
    /// `false`: show at most once per device (after `markSeen`), until `resetSeen`.
    static var forceShowTryCartShopAllIntroEveryTime: Bool = true

    static func shouldPresent(_ id: AppBannerID) -> Bool {
        switch id {
        case .tryCartShopAllIntro:
            if forceShowTryCartShopAllIntroEveryTime { return true }
            return !hasSeen(id)
        }
    }

    static func markSeen(_ id: AppBannerID) {
        defaults.set(true, forKey: seenKeyPrefix + id.rawValue)
    }

    static func hasSeen(_ id: AppBannerID) -> Bool {
        defaults.bool(forKey: seenKeyPrefix + id.rawValue)
    }

    static func resetSeen(_ id: AppBannerID) {
        defaults.removeObject(forKey: seenKeyPrefix + id.rawValue)
    }
}
