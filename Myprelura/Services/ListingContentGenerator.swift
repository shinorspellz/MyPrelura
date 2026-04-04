import Foundation

/// Generates title, description, and tags from detected category, colour, and style using templates. No external APIs.
enum ListingContentGenerator {
    /// Title: "{colour} {style} {category}" or "{colour} {category}" if style is nil.
    static func title(colour: String?, style: String?, category: String?) -> String? {
        guard let c = colour?.trimmingCharacters(in: .whitespaces), !c.isEmpty,
              let cat = category?.trimmingCharacters(in: .whitespaces), !cat.isEmpty else { return nil }
        if let s = style?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            return "\(c) \(s) \(cat)"
        }
        return "\(c) \(cat)"
    }

    /// Description: "{colour} {category} in {condition} condition. Perfect for {style} outfits." or "{colour} {category} in great condition." if style missing.
    static func description(colour: String?, category: String?, style: String?, condition: String? = "great") -> String? {
        guard let c = colour?.trimmingCharacters(in: .whitespaces), !c.isEmpty,
              let cat = category?.trimmingCharacters(in: .whitespaces), !cat.isEmpty else { return nil }
        let cond = (condition?.trimmingCharacters(in: .whitespaces)).flatMap { $0.isEmpty ? nil : $0 } ?? "great"
        if let s = style?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            return "\(c) \(cat) in \(cond) condition. Perfect for \(s.lowercased()) outfits."
        }
        return "\(c) \(cat) in \(cond) condition."
    }

    /// Tags: [category, "colour category", style?, "style category"?], lowercased and deduplicated.
    static func tags(colour: String?, style: String?, category: String?) -> [String]? {
        guard let cat = category?.trimmingCharacters(in: .whitespaces), !cat.isEmpty else { return nil }
        var list: [String] = []
        let catLower = cat.lowercased()
        list.append(catLower)
        if let c = colour?.trimmingCharacters(in: .whitespaces), !c.isEmpty {
            list.append("\(c.lowercased()) \(catLower)")
        }
        if let s = style?.trimmingCharacters(in: .whitespaces), !s.isEmpty {
            let sLower = s.lowercased()
            list.append(sLower)
            list.append("\(sLower) \(catLower)")
        }
        return list.isEmpty ? nil : Array(Set(list)).sorted()
    }
}
