import Foundation

/// Calls Google Places API (Autocomplete) for location suggestions. UK-only, locality-level (cities/towns).
/// API key from Secrets.plist (GOOGLE_PLACES_API_KEY). Falls back to local list when key is missing or request fails.
final class GooglePlacesService {

    static let shared = GooglePlacesService()

    private let baseURL = URL(string: "https://maps.googleapis.com/maps/api/place/autocomplete/json")!
    private let maxResults = 20

    /// API key from Secrets.plist only — no Xcode scheme or env vars required. Edit Prelura-swift/Secrets.plist.
    private var apiKey: String {
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url) as? [String: Any],
           let key = dict["GOOGLE_PLACES_API_KEY"] as? String, !key.isEmpty {
            return key.trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    var isConfigured: Bool {
        let key = apiKey
        return !key.isEmpty && !key.hasPrefix("YOUR_") && key != "YOUR_GOOGLE_PLACES_API_KEY"
    }

    /// Request body for legacy Autocomplete: we use GET with query items.
    struct AutocompleteResponse: Decodable {
        let predictions: [Prediction]?
        let status: String?
        let error_message: String?

        struct Prediction: Decodable {
            let description: String?
            let place_id: String?
        }
    }

    /// Returns location suggestions from Google Places (UK, localities). Returns empty array on failure or if key not set.
    func suggestions(for query: String) async -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        guard isConfigured else {
            #if DEBUG
            print("[Places] No API key. Add GOOGLE_PLACES_API_KEY to Prelura-swift/Secrets.plist")
            #endif
            return []
        }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "input", value: q),
            URLQueryItem(name: "key", value: apiKey),
            URLQueryItem(name: "components", value: "country:gb"),
            URLQueryItem(name: "types", value: "geocode"),
        ]
        guard let url = components.url else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(AutocompleteResponse.self, from: data)
            #if DEBUG
            if decoded.status != "OK" {
                print("[Places] status=\(decoded.status ?? "nil"), error=\(decoded.error_message ?? "none")")
            }
            #endif
            if decoded.status == "OK", let predictions = decoded.predictions {
                return predictions.compactMap { $0.description }.filter { !$0.isEmpty }.prefix(maxResults).map { $0 }
            }
            return []
        } catch {
            #if DEBUG
            print("[Places] Request failed: \(error.localizedDescription)")
            #endif
            return []
        }
    }
}
