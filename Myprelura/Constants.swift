import Foundation

enum Constants {
    /// Same production GraphQL endpoint as the consumer Prelura app.
    static let graphQLBaseURL = "https://prelura.voltislabs.uk/graphql/"
    static let apiTimeout: TimeInterval = 60

    /// Same `UserDefaults` key as consumer `Prelura_swiftApp` (`kAppearanceMode`).
    static let appearanceModeStorageKey = "appearance_mode"

    /// Public web host (universal links / sharing); paths match consumer `Constants.publicWebItemLinkBaseURL`.
    static let publicWebBaseURL = "https://prelura.uk"

    static func publicProfileURL(username: String) -> URL? {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !u.isEmpty else { return nil }
        let enc = u.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? u
        return URL(string: "\(publicWebBaseURL)/\(enc)")
    }

    /// Listing page on the public site (`/item/{listingCodeOrId}`), same contract as the shopper app.
    static func publicProductURL(productId: Int, listingCode: String?) -> URL? {
        let trimmed = listingCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let slug: String = {
            if !trimmed.isEmpty {
                return trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
            }
            return "\(productId)"
        }()
        return URL(string: "\(publicWebBaseURL)/item/\(slug)")
    }
}
