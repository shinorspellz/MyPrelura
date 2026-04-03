import Foundation

/// Resolves relative or hostless media paths from GraphQL into loadable `URL`s (same idea as consumer `Constants` + CDN base).
enum MediaURL {
    /// API host for resolving `/media/...` paths (matches `Constants.graphQLBaseURL`).
    private static var apiOrigin: String {
        guard let u = URL(string: Constants.graphQLBaseURL),
              let scheme = u.scheme,
              let host = u.host
        else { return "https://prelura.voltislabs.uk" }
        let port = u.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }

    static func resolvedURL(from string: String?) -> URL? {
        guard var s = string?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("//") {
            s = "https:\(s)"
        }
        if let u = URL(string: s), u.scheme != nil, u.host != nil {
            return u
        }
        if s.hasPrefix("/") {
            return URL(string: apiOrigin + s)
        }
        return URL(string: apiOrigin + "/" + s)
    }
}
