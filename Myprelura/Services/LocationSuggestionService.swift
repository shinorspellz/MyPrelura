import Foundation

/// Loads and searches a bundled list of cities, towns, and countries only (no street addresses).
/// No API dependency — all data is local. Suggestions are restricted to locality/country level.
struct LocationSuggestionService {
    struct Entry: Decodable {
        /// Display string shown in the field when selected (e.g. "Peterborough, UK", "United Kingdom").
        let display: String
        /// Lowercased search terms; we match user input against these.
        let searchTerms: [String]
    }

    private let entries: [Entry]
    private let maxSuggestions = 20

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: "LocationSuggestions", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else {
            self.entries = Self.fallbackEntries()
            return
        }
        self.entries = decoded
    }

    /// Returns suggestions whose search terms match the query (prefix or contains). Only cities, towns, countries — no addresses.
    func suggestions(for query: String) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let matched = entries.filter { entry in
            entry.searchTerms.contains { term in
                term.hasPrefix(q) || term.contains(" " + q) || term.contains(q + " ")
            }
        }
        return matched.prefix(maxSuggestions).map(\.display)
    }

    /// Async: Google Places only (bundled list disabled for testing). Use this for the location field.
    func suggestionsAsync(for query: String) async -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return await GooglePlacesService.shared.suggestions(for: q)
    }

    /// Fallback if JSON is missing: UK-only list (app users are UK-only).
    private static func fallbackEntries() -> [Entry] {
        var list: [Entry] = []
        list.append(Entry(display: "United Kingdom", searchTerms: ["united kingdom", "uk"]))
        list.append(Entry(display: "UK", searchTerms: ["uk", "united kingdom"]))
        let cities: [(name: String, code: String)] = [
            ("London", "UK"), ("Manchester", "UK"), ("Birmingham", "UK"), ("Leeds", "UK"),
            ("Glasgow", "UK"), ("Liverpool", "UK"), ("Bristol", "UK"), ("Sheffield", "UK"),
            ("Edinburgh", "UK"), ("Cardiff", "UK"), ("Belfast", "UK"), ("Newcastle", "UK"),
            ("Nottingham", "UK"), ("Southampton", "UK"), ("Brighton", "UK"), ("Leicester", "UK"),
            ("Coventry", "UK"), ("Hull", "UK"), ("Bradford", "UK"), ("Stoke-on-Trent", "UK"),
            ("Wolverhampton", "UK"), ("Derby", "UK"), ("Plymouth", "UK"), ("Reading", "UK"),
            ("Peterborough", "UK"), ("Northampton", "UK"), ("Luton", "UK"), ("Aberdeen", "UK"),
            ("Bournemouth", "UK"), ("Oxford", "UK"), ("Cambridge", "UK"), ("York", "UK"),
            ("Preston", "UK"), ("Bolton", "UK"), ("Blackburn", "UK"), ("Burnley", "UK"),
            ("Rochdale", "UK"), ("Oldham", "UK"), ("Wigan", "UK"), ("Warrington", "UK"),
            ("Crewe", "UK"), ("Chester", "UK"), ("Lancaster", "UK"), ("Carlisle", "UK"),
            ("Sunderland", "UK"), ("Middlesbrough", "UK"), ("Doncaster", "UK"), ("Rotherham", "UK"),
            ("Barnsley", "UK"), ("Wakefield", "UK"), ("Huddersfield", "UK"), ("Halifax", "UK"),
            ("Grimsby", "UK"), ("Lincoln", "UK"), ("Norwich", "UK"), ("Ipswich", "UK"),
            ("Colchester", "UK"), ("Southend", "UK"), ("Slough", "UK"), ("Portsmouth", "UK"),
            ("Exeter", "UK"), ("Torquay", "UK"), ("Bath", "UK"), ("Swindon", "UK"),
            ("Gloucester", "UK"), ("Cheltenham", "UK"), ("Worcester", "UK"), ("Hereford", "UK"),
            ("Shrewsbury", "UK"), ("Telford", "UK"), ("Stafford", "UK"), ("Burton upon Trent", "UK"),
            ("Milton Keynes", "UK"), ("Bedford", "UK"), ("St Albans", "UK"), ("Hemel Hempstead", "UK"),
            ("Stevenage", "UK"), ("Dundee", "UK"), ("Inverness", "UK"), ("Swansea", "UK"),
            ("Newport", "UK"), ("Derry", "UK"), ("Lisburn", "UK"), ("Newry", "UK"),
        ]
        for city in cities {
            let display = "\(city.name), \(city.code)"
            let terms = [city.name.lowercased(), "\(city.name.lowercased()) \(city.code.lowercased())", city.code.lowercased()]
            list.append(Entry(display: display, searchTerms: terms))
        }
        return list
    }
}
