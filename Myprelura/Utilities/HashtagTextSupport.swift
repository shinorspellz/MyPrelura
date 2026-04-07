import Foundation

/// Shared parsing for `#tags` in listing descriptions (sell flow, product detail, staff app).
enum HashtagTextSupport {
    /// ICU: letters, numbers, underscore after `#` (supports non-ASCII letters).
    static let hashtagPattern = "#(?:[\\p{L}\\p{N}_]+)"

    static func parseHashtagSegments(_ string: String) -> [(text: String, isHashtag: Bool)] {
        var result: [(String, Bool)] = []
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) else {
            return [(string, false)]
        }
        let range = NSRange(string.startIndex..., in: string)
        var lastEnd = string.startIndex
        regex.enumerateMatches(in: string, options: [], range: range) { match, _, _ in
            guard let match = match, let r = Range(match.range, in: string) else { return }
            if lastEnd < r.lowerBound {
                result.append((String(string[lastEnd..<r.lowerBound]), false))
            }
            result.append((String(string[r]), true))
            lastEnd = r.upperBound
        }
        if lastEnd < string.endIndex {
            result.append((String(string[lastEnd...]), false))
        }
        return result.isEmpty ? [(string, false)] : result
    }

    /// Unique hashtags in first-seen order (includes `#` prefix).
    static func uniqueHashtags(in description: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern, options: []) else { return [] }
        let range = NSRange(description.startIndex..., in: description)
        var seen = Set<String>()
        var ordered: [String] = []
        regex.enumerateMatches(in: description, options: [], range: range) { match, _, _ in
            guard let match = match, let r = Range(match.range, in: description) else { return }
            let tag = String(description[r])
            if seen.insert(tag).inserted {
                ordered.append(tag)
            }
        }
        return ordered
    }
}
