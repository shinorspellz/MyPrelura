import Foundation

/// App-wide constants. API base URLs point to the Prelura backend.
///
/// **Backend repository (do not modify from this app):**
/// https://github.com/VoltisLab/prelura-app
///
/// This app uses the backend's GraphQL API at the URLs below; schema and endpoints are shared with the Flutter app and other clients.
struct Constants {
    // GraphQL Endpoints (backend: https://github.com/VoltisLab/prelura-app)
    static let graphQLBaseURL = "https://prelura.voltislabs.uk/graphql/"
    static let graphQLUploadURL = "https://prelura.voltislabs.uk/graphql/uploads/"
    /// WebSocket for chat (same host as GraphQL so messages send/save to the same backend).
    static let chatWebSocketBaseURL = "wss://prelura.voltislabs.uk/ws/chat/"
    /// Django `ConversationsConsumer`: inbox list sync + typing for threads the user is in (not per-room chat).
    static let conversationsWebSocketURL = "wss://prelura.voltislabs.uk/ws/conversations/"
    
    /// Consumer marketing site (Wearhouse): legal + help HTML. Staff app loads the same public pages for parity with the shopper app.
    static let publicWebsiteBaseURL = "https://mywearhouse.co.uk"

    static var termsAndConditionsURL: String { "\(publicWebsiteBaseURL)/terms/" }
    static var privacyPolicyURL: String { "\(publicWebsiteBaseURL)/privacy/" }
    static var acknowledgementsURL: String { "\(publicWebsiteBaseURL)/acknowledgements/" }
    static let hmrcReportingURL = "https://www.gov.uk/government/organisations/hm-revenue-customs/contact/report-fraud-or-an-untrustworthy-website"

    static var helpHowToUseWearhouseURL: String { "\(publicWebsiteBaseURL)/help/how-to-use" }
    static var helpArticleCancelOrderURL: String { "\(publicWebsiteBaseURL)/help/cancel-order" }
    static var helpArticleRefundsURL: String { "\(publicWebsiteBaseURL)/help/refunds" }
    static var helpArticleDeliveryURL: String { "\(publicWebsiteBaseURL)/help/delivery" }
    static var helpArticleOrderShippedURL: String { "\(publicWebsiteBaseURL)/help/order-shipped" }
    static var helpArticleCollectionPointURL: String { "\(publicWebsiteBaseURL)/help/collection-point" }
    static var helpArticleDeliveredNotReceivedURL: String { "\(publicWebsiteBaseURL)/help/delivered-not-received" }
    static var helpArticleVacationModeURL: String { "\(publicWebsiteBaseURL)/help/vacation-mode" }
    static var helpArticleTrustedSellerURL: String { "\(publicWebsiteBaseURL)/help/trusted-seller" }
    
    /// Django-served universal link base (`/.well-known/...`, `/app/u/`, `/join/`).
    static let universalLinksAPIBaseURL = "https://prelura.voltislabs.uk"
    /// Used when inviting contacts (share sheet / SMS).
    static let inviteToPreluraURL = "https://prelura.voltislabs.uk/join/"
    /// Product share links (`/item/…`). Uses the **API host** for working universal links until `mywearhouse.co.uk` serves AASA (see consumer app `Constants`).
    static var publicWebItemLinkBaseURL: String { universalLinksAPIBaseURL }
    
    // API Configuration
    static let apiTimeout: TimeInterval = 60.0

    // MARK: - Myprelura (staff) — same keys / URLs as legacy admin app
    static let prefilledStaffUsername = "testuser"
    static let prefilledStaffPassword = "Password123!!!"
    /// Matches `kAppearanceMode` in `Prelura_swiftApp`.
    static let appearanceModeStorageKey = "appearance_mode"
    /// Alias for staff settings UI (same host as `publicWebItemLinkBaseURL`).
    static var publicWebBaseURL: String { publicWebItemLinkBaseURL }
    /// HEAD target for Console “Public web” probe (`/` often blocks HEAD on SPAs; robots.txt is reliable).
    static var publicWebHealthProbeURL: String { "\(publicWebItemLinkBaseURL)/robots.txt" }

    static func publicProfileURL(username: String) -> URL? {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !u.isEmpty else { return nil }
        let enc = u.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? u
        return URL(string: "\(universalLinksAPIBaseURL)/app/u/\(enc)/")
    }

    static func publicProductURL(productId: Int, listingCode: String?) -> URL? {
        let trimmed = listingCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let slug: String = {
            if !trimmed.isEmpty {
                return trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            }
            return "\(productId)"
        }()
        return URL(string: "\(publicWebItemLinkBaseURL)/item/\(slug)")
    }
}
