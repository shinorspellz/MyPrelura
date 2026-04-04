import Foundation
import UIKit

/// Detected event from query for response tone (happy → cheerful, sad → neutral).
enum DetectedEvent {
    case none
    case happy   // birthday, wedding, festival, holiday
    case sad     // funeral, breakup
}

/// Result of parsing a search query for colours, categories, price, and free text.
/// Used to build API search/filters and to show conversational replies.
struct ParsedSearch {
    /// Search string to send to the API (includes colour/category/synonym terms for backend to match). Does not include size — size is applied client-side.
    var searchText: String
    /// Ordered list of search queries to try in order: multi-term first (e.g. "floral tshirt"), then single terms (e.g. "floral", "tshirt"). Enables hierarchy: try narrow query first, then broader.
    var searchQueryCandidates: [String]
    /// Resolved parent category if detected from query (e.g. "Women", "Men").
    var categoryOverride: String?
    /// Colour names we inferred (from app colours or aliases); for hint only if we mapped aliases.
    var appliedColourNames: [String]
    /// When we mapped an alias (e.g. "camo" → "Green"), show this message.
    var closestMatchHint: String?
    /// When we corrected a likely typo (e.g. "derss" → "Dress"), show "Do you mean 'Dress'?" in the reply.
    var spellingCorrectionHint: (original: String, corrected: String)?
    /// Max price when user says "under £X", "cheap", etc.
    var priceMax: Double?
    /// Detected event for response tone (birthday → cheerful, funeral → neutral).
    var detectedEvent: DetectedEvent = .none
    /// Size from "size 10", "size M", etc. Applied client-side filter; not sent in API search (backend text search doesn't match size well).
    var sizeTerm: String?
}

/// Lightweight "learning" search: parses natural language for colours and categories,
/// supports typos (fuzzy match) and maps common colour names to app colours.
/// Backend is not modified; we only produce a search string and optional category.
///
/// Training data: Prelura AI Training Dataset — Category & Colour Detection (100 Query Types).
/// Covers: Basic + Conversational colour+category, Multi-colour, Relative colour, Style+colour,
/// Price+colour, Material+colour, Size+colour, Event, Casual/messy queries.
final class AISearchService {

    // MARK: - App vocabulary (training doc + Sell flow)

    
    static let appColours: [String] = [
        "Black", "White", "Red", "Blue", "Green", "Yellow", "Pink", "Purple",
        "Orange", "Brown", "Grey", "Beige", "Navy", "Maroon", "Teal"
    ]
    
    /// Parent categories (feed filter)
    static let parentCategories: [String] = ["All", "Women", "Men", "Kids", "Toddlers", "Boys", "Girls"]
    
    /// Subcategories (from Category model) for keyword matching
    static let subCategories: [String] = [
        "Clothing", "Clothes", "Shoes", "Footwear", "Accessories", "Electronics",
        "Home", "Beauty", "Books", "Sports"
    ]
    
    /// Multi-word colour phrases (checked before single-word matching; training doc: "sky blue", "light blue").
    private static let colourPhrases: [(phrase: String, appColour: String)] = [
        ("sky blue", "Blue"), ("light blue", "Blue"), ("dark blue", "Navy"), ("navy blue", "Navy"), ("royal blue", "Blue"),
        ("dark green", "Green"), ("light green", "Green"), ("burgundy red", "Maroon"), ("off white", "White")
    ]

    /// Map common colour names / aliases to our app colour names (training doc: navy→dark blue, cream→off white, etc.).
    static let colourAliases: [String: String] = [
        // Greens (doc: mint→pale green, olive→muted green)
        "camo": "Green", "camouflage": "Green", "olive": "Green", "forest": "Green",
        "mint": "Green", "sage": "Green", "lime": "Green", "emerald": "Green",
        "dark green": "Green", "light green": "Green", "army": "Green",
        "greed": "Green",
        // Reds / wine (doc: wine→burgundy)
        "wine": "Maroon", "burgundy": "Maroon", "burgundy red": "Maroon",
        "claret": "Maroon", "bordeaux": "Maroon",
        "crimson": "Red", "scarlet": "Red", "dark red": "Maroon", "cherry": "Red",
        // Blues (doc: navy→dark blue, royal blue→bright blue, sky blue→light blue)
        "navy": "Navy", "navy blue": "Navy", "midnight": "Navy", "royal blue": "Blue",
        "sky blue": "Blue", "light blue": "Blue", "dark blue": "Navy", "cobalt": "Blue",
        // Neutrals (doc: cream→off white, sand→beige)
        "tan": "Beige", "sand": "Beige", "cream": "White", "ivory": "White", "off white": "White",
        "charcoal": "Grey", "silver": "Grey", "gray": "Grey", "slate": "Grey",
        "taupe": "Brown", "khaki": "Beige", "mocha": "Brown", "chocolate": "Brown",
        // Pinks / purples
        "magenta": "Pink", "rose": "Pink", "blush": "Pink", "lavender": "Purple",
        "violet": "Purple", "plum": "Purple", "mauve": "Purple",
        // Yellows / oranges
        "gold": "Yellow", "mustard": "Yellow", "amber": "Orange", "coral": "Orange",
        "peach": "Orange", "terracotta": "Orange", "rust": "Orange",
        // Multi-colour expansion (doc: blue and green → teal, turquoise, aqua)
        "teal": "Teal", "turquoise": "Teal", "aqua": "Teal"
    ]

    /// Category / product term synonyms (training doc: jumper→sweater, trainers→sneakers; query 63 "cotton white t shirt").
    static let categorySynonyms: [String: String] = [
        "jumper": "sweater", "jumpers": "sweater", "sweaters": "sweater",
        "trainers": "sneakers", "sneaker": "sneakers", "trainer": "sneakers",
        "coat": "jacket", "coats": "jacket",
        "tshirt": "tee", "t-shirt": "tee", "t shirt": "tee", "tshirts": "tee",
        "bag": "handbag", "bags": "handbag", "handbags": "handbag",
        "hoody": "hoodie", "hoodies": "hoodie",
        "trouser": "trousers", "pant": "trousers", "pants": "trousers",
        "heel": "heels", "boot": "boots"
    ]

    /// Greetings / non-product words — don't use as fallback term (avoids "here are some hellos").
    static let nonProductWords: Set<String> = [
        "hello", "hi", "hey", "thanks", "thank", "bye", "ok", "okay",
        "world", "there", "help", "please", "yes", "no"
    ]

    /// 100 salutation phrases: if the user's message (normalized) matches any of these, the AI responds with a greeting instead of searching. See AI Dataset.md § Salutations.
    static let salutations: Set<String> = [
        "hi", "hello", "hey", "hey there", "hi there", "hello there",
        "heyy", "hiii", "hey hey", "hello hello", "hiya", "heya",
        "yo", "yoo", "yo yo", "sup", "what's up", "hey what's up", "hi what's up", "hello what's up",
        "good morning", "morning", "good afternoon", "afternoon", "good evening", "evening", "good day",
        "greetings", "greetings friend", "howdy", "howdy there",
        "hey friend", "hi friend", "hello friend", "hey mate", "hi mate", "hello mate",
        "hey buddy", "hi buddy", "hello buddy", "hey pal", "hi pal", "hello pal",
        "hey everyone", "hi everyone", "hello everyone", "hey guys", "hi guys", "hello guys",
        "hey team", "hi team", "hello team", "hey again", "hi again", "hello again",
        "hey how are you", "hi how are you", "hello how are you",
        "hey how's it going", "hi how's it going", "hello how's it going",
        "hey how you doing", "hi how you doing", "hello how you doing",
        "hey what's going on", "hi what's going on", "hello what's going on",
        "hey what's happening", "hi what's happening", "hello what's happening",
        "hey what's new", "hi what's new", "hello what's new",
        "hey good morning", "hi good morning", "hello good morning",
        "hey good evening", "hi good evening", "hello good evening",
        "hey good afternoon", "hi good afternoon", "hello good afternoon",
        "hey there friend", "hi there friend", "hello there friend",
        "hey there mate", "hi there mate", "hello there mate",
        "hey there buddy", "hi there buddy", "hello there buddy",
        "hey hey there", "hi hi", "hello hello there",
        "hey how's everything", "hi how's everything", "hello how's everything",
        "hey what's good", "hi what's good", "hello what's good"
    ]

    /// 100 social/greeting questions (e.g. "Hi, how are you?", "Hey, what's up?") that get a greeting reply, not a product search. Stored normalized (no punctuation). See AI Dataset.md § Social greeting Q&A.
    static let socialGreetingPhrases: Set<String> = [
        "hi how are you", "hey how are you", "hello how are you",
        "hi how are you today", "hey how are you today", "hello how are you today",
        "hi hows it going", "hey hows it going", "hello hows it going",
        "hi how you doing", "hey how you doing", "hello how you doing",
        "hi how are you doing", "hey how are you doing", "hello how are you doing",
        "hi whats up", "hey whats up", "hello whats up",
        "hi whats new", "hey whats new", "hello whats new",
        "hi hows your day", "hey hows your day", "hello hows your day",
        "hi hows your day going", "hey hows your day going", "hello hows your day going",
        "hi hows everything", "hey hows everything", "hello hows everything",
        "hi how have you been", "hey how have you been", "hello how have you been",
        "hi how do you do", "hey how do you do", "hello how do you do",
        "hi whats going on", "hey whats going on", "hello whats going on",
        "hi whats happening", "hey whats happening", "hello whats happening",
        "hi whats good", "hey whats good", "hello whats good",
        "hi hows life", "hey hows life", "hello hows life",
        "hi good to see you", "hey good to see you", "hello good to see you",
        "hi nice to meet you", "hey nice to meet you", "hello nice to meet you",
        "hi good morning how are you", "hey good morning how are you", "hello good morning how are you",
        "hi there how are you", "hey there how are you", "hello there how are you",
        "hi how have you been", "hey how have you been", "hello how have you been",
        "hi whats up today", "hey whats up today", "hello whats up today",
        "hi how is your day", "hey how is your day", "hello how is your day",
        "hi how are things", "hey how are things", "hello how are things",
        "hi how have you been doing", "hey how have you been doing", "hello how have you been doing",
        "hi great to see you", "hey great to see you", "hello great to see you",
        "hi lovely to meet you", "hey lovely to meet you", "hello lovely to meet you",
        "hi hope you are well", "hey hope you are well", "hello hope you are well",
        "hi hope youre well", "hey hope youre well", "hello hope youre well",
        "hi how you been", "hey how you been", "hello how you been",
        "hi whats the vibe", "hey whats the vibe", "hello whats the vibe",
        "hi hows your morning", "hey hows your morning", "hello hows your morning",
        "hi hows your evening", "hey hows your evening", "hello hows your evening",
        "hi good to chat", "hey good to chat", "hello good to chat",
        "hi good afternoon how are you", "hey good afternoon how are you", "hello good afternoon how are you",
        "hi good evening how are you", "hey good evening how are you", "hello good evening how are you",
        "hi how is it going", "hey how is it going", "hello how is it going",
        "hi whats cracking", "hey whats cracking", "hello whats cracking",
        "hi how are we", "hey how are we", "hello how are we",
        "hi how are you feeling", "hey how are you feeling", "hello how are you feeling",
        "hi alright", "hey alright", "hello alright",
        "hi you good", "hey you good", "hello you good",
        "hi everything good", "hey everything good", "hello everything good"
    ]

    /// Category keywords for matching (training doc + Batch 3: dress, scarf, cargo trousers, cardigan, blazer, joggers, etc.); fuzzy-matched for typos.
    static let categoryKeywords: [String] = [
        "dress", "dresses", "hoodie", "hoodies", "jacket", "jackets", "coat", "coats",
        "jeans", "trousers", "skirt", "skirts", "heels", "boots", "trainers", "sneakers",
        "bag", "handbag", "handbags", "jumper", "sweater", "sweaters", "tee", "tshirt", "shirt", "shirts", "top", "tops",
        "blouse", "blouses", "scarf", "scarves", "outfit", "outfits",
        "cardigan", "cardigans", "blazer", "blazers", "joggers", "jogger", "cargo",
        "flannel", "bomber"
    ]

    /// Conversational "want" prefixes/suffixes to strip so "I need a floral tshirt" → "floral tshirt". ~100 variants (training doc §100; user: "I need a", "I want a", "I'm looking for", etc.). Stripped in order of length (longest first) so "i am looking for a" is removed before "looking for".
    private static let wantPhrasesLongestFirst: [String] = {
        let raw: [String] = [
            "i am looking for a", "i'm looking for a", "im looking for a", "i am looking for", "i'm looking for", "im looking for", "looking for a", "looking for",
            "i would like to find a", "i'd like to find a", "id like to find a", "i would like to find", "i'd like to find", "id like to find", "like to find a", "like to find",
            "i am searching for a", "i'm searching for a", "im searching for a", "i am searching for", "i'm searching for", "im searching for", "searching for a", "searching for",
            "i am in the market for a", "i'm in the market for a", "im in the market for a", "in the market for a", "in the market for",
            "i need to find a", "i need to find", "need to find a", "need to find",
            "i want to find a", "i want to find", "want to find a", "want to find",
            "i am trying to find a", "i'm trying to find a", "im trying to find a", "trying to find a", "trying to find",
            "can you find me a", "can you find me", "could you find me a", "could you find me",
            "can you show me a", "can you show me", "could you show me a", "could you show me",
            "do you have a", "do you have any", "do u have a", "do u have any", "you have a", "you have any",
            "have you got a", "have you got any", "got any", "got a",
            "can i get a", "can i get", "could i get a", "could i get",
            "i need a", "i need", "need a", "need",
            "i want a", "i want", "want a", "want",
            "show me a", "show me some", "show me",
            "find me a", "find me",
            "get me a", "get me",
            "i'm after a", "im after a", "i am after a", "after a", "after",
            "i'm on the hunt for a", "im on the hunt for a", "on the hunt for a", "on the hunt for",
            "i'm after", "i am after",
            "i am after a", "i am after",
            "looking to buy a", "looking to buy", "looking to get a", "looking to get",
            "i'd love a", "id love a", "i would love a", "i'd love", "id love", "love a", "love",
            "i'm hoping to find a", "im hoping to find a", "hoping to find a", "hoping to find",
            "i'm trying to find a", "im trying to find a",
            "i am hoping for a", "i'm hoping for a", "im hoping for a", "hoping for a", "hoping for",
            "on the lookout for a", "on the lookout for", "lookout for a", "lookout for",
            "in need of a", "in need of",
            "searching for a", "searching for",
            "in search of a", "in search of", "search of a", "search of",
            "after something like a", "after something like", "something like a", "something like",
            "something along the lines of a", "something along the lines of",
            "after a", "after",
            "want something like a", "want something like",
            "need something like a", "need something like",
            "asap", "pls", "please", "thanks", "thank you"
        ]
        return raw.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }.filter { !$0.isEmpty }.sorted { $0.count > $1.count }
    }()

    /// Legacy list kept for any suffix stripping; prefer wantPhrasesLongestFirst for prefix.
    private static let conversationalStrippers: [String] = [
        "do you have", "do you have a", "do you have any", "do u have", "do u have a",
        "im looking for", "i'm looking for", "i am looking for", "looking for", "looking for a",
        "im searching for", "i'm searching for", "i am searching for", "searching for", "searching for a",
        "i want", "i want a", "i need", "i need a", "show me", "show me a", "show me some",
        "can i get", "can you show", "got any", "have you got", "need a", "want a",
        "asap", "pls", "please", "thanks", "thank you"
    ]

    /// Words to drop from the final search string (articles, conjunctions, filler, colour modifiers).
    private static let searchStopwords: Set<String> = [
        "a", "an", "the", "do", "you", "have", "has", "get", "got", "for", "to", "of",
        "im", "i'm", "me", "and", "or", "but", "that", "this", "is", "it", "in", "on",
        "lighter", "darker", "light", "dark", "almost", "soft", "pale", "faded", "bright", "not",
        "than", "something", "close"
    ]

    /// Happy events → cheerful response (training doc §Event Queries 81–90: wedding, party, graduation, holiday, birthday, date night, travel).
    static let happyEventWords: [String] = [
        "birthday", "wedding", "festival", "holiday", "holidays", "celebration", "party", "vacation", "trip",
        "graduation", "date night", "travel"
    ]

    /// Sad events → neutral response; doc: funeral, breakup.
    static let sadEventWords: [String] = ["funeral", "breakup", "break up", "memorial"]

    /// Season terms kept in search (training doc: "yellow scarf for winter"; queries 89–90 winter, autumn).
    static let seasonKeywords: [String] = ["winter", "summer", "autumn", "spring"]

    /// Material terms kept in search (training doc §Material + Colour 61–70: leather, denim, cotton, wool, silk, linen).
    static let materialKeywords: [String] = ["leather", "denim", "cotton", "wool", "silk", "linen"]

    /// Style terms kept in search (training doc §Style + Colour 41–50: vintage, minimalist, oversized, streetwear, Y2K, casual, elegant, sporty, retro, relaxed).
    static let styleKeywords: [String] = ["vintage", "minimalist", "oversized", "streetwear", "y2k", "casual", "elegant", "sporty", "retro", "relaxed"]

    /// Price patterns (training doc §Price + Colour 51–60: "under £20", "under £50", "cheap", etc.).
    private static let pricePattern = try? NSRegularExpression(pattern: #"under\s*[£$]?\s*(\d+)"#, options: .caseInsensitive)
    private static let budgetWords: [(word: String, max: Double)] = [
        ("cheap", 30), ("budget", 35), ("affordable", 40)
    ]
    
    /// Max Levenshtein distance to consider a typo match (e.g. "gren" → "Green")
    private let maxTypoDistance = 2
    
    /// Minimum length of word to apply fuzzy match (avoid matching "a", "in", etc.)
    private let minLengthForFuzzy = 3
    
    // MARK: - Parse query

    /// Strip conversational "want" phrasing so "I need a floral tshirt" → "floral tshirt". First strips leading salutations (hi, hello, hey...) so "Hi I need a floral shirt" works; then uses ~100 want phrases (longest first); then strips suffix phrases.
    private func normalizeConversational(_ query: String) -> String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return q }
        // Strip leading salutations/greetings so "Hi I need a floral shirt" → "i need a floral shirt" (then want phrase strips to "floral shirt").
        let leadingSalutations: [String] = [
            "hi there", "hey there", "hello there", "hi again", "hey again", "hello again",
            "good morning", "good afternoon", "good evening", "good day",
            "hey friend", "hi friend", "hello friend", "hey mate", "hi mate", "hello mate",
            "hey buddy", "hi buddy", "hello buddy", "hey pal", "hi pal", "hello pal",
            "hey everyone", "hi everyone", "hello everyone", "hey guys", "hi guys", "hello guys",
            "hey team", "hi team", "hello team",
            "hi lenny", "hey lenny", "hello lenny", "hey lenny,",
            "hi", "hey", "hello", "heyy", "hiii", "hey hey", "hello hello", "hiya", "heya",
            "yo", "yoo", "sup", "greetings", "howdy", "hiya"
        ]
        let salutationsLongestFirst = leadingSalutations.sorted { $0.count > $1.count }
        var didStripSalutation = true
        while didStripSalutation {
            didStripSalutation = false
            for prefix in salutationsLongestFirst {
                if q.hasPrefix(prefix + " ") {
                    q = String(q.dropFirst(prefix.count + 1)).trimmingCharacters(in: .whitespaces)
                    didStripSalutation = true
                    break
                }
                if q == prefix {
                    q = ""
                    return q
                }
            }
        }
        for phrase in Self.wantPhrasesLongestFirst {
            if q.hasPrefix(phrase) {
                q = String(q.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        for phrase in Self.conversationalStrippers {
            if q.hasSuffix(phrase) {
                q = String(q.dropLast(phrase.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return q.trimmingCharacters(in: .whitespaces)
    }

    /// Expand synonyms in the query (jumper→sweater, etc.) for better search.
    private func expandSynonyms(_ query: String) -> String {
        var q = query.lowercased()
        for (from, to) in Self.categorySynonyms {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: from) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                q = regex.stringByReplacingMatches(in: q, range: NSRange(q.startIndex..., in: q), withTemplate: to)
            }
        }
        return q
    }

    /// Maps common category word variants (possessive and plural) to parent category. Used so "jeans women's", "dress boys", "shoes boy's" set category and don't pollute search text.
    private static func parentCategoryFromWord(_ lower: String) -> String? {
        switch lower {
        case "woman's", "women's", "womens", "women": return "Women"
        case "man's", "men's", "mens", "men": return "Men"
        case "boy's", "boys'", "boys": return "Boys"
        case "girl's", "girls'", "girls": return "Girls"
        case "kid's", "kids'", "kids": return "Kids"
        case "toddler's", "toddlers'", "toddlers": return "Toddlers"
        default: return nil
        }
    }

    /// Extract size from "size M", "size 32", "size 6", "size L", etc. (training doc: size + colour queries).
    private func extractSizeTerm(from query: String) -> String? {
        let lower = query.lowercased()
        let pattern = #"size\s+([a-z0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
              let range = Range(match.range(at: 1), in: lower) else { return nil }
        let size = String(lower[range])
        let validSizes = ["xs", "s", "m", "l", "xl", "xxl", "small", "medium", "large"]
        if validSizes.contains(size) || size.allSatisfy(\.isNumber) { return size }
        return nil
    }

    /// Extract max price from "under £40", "cheap", "budget", etc.
    private func extractPriceMax(from query: String) -> Double? {
        let lower = query.lowercased()
        if let pattern = Self.pricePattern,
           let match = pattern.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let range = Range(match.range(at: 1), in: lower),
           let value = Double(lower[range]) {
            return value
        }
        for (word, max) in Self.budgetWords where lower.contains(word) {
            return max
        }
        return nil
    }

    /// Detect event for response tone.
    private func detectEvent(from query: String) -> DetectedEvent {
        let lower = query.lowercased()
        if Self.sadEventWords.contains(where: { lower.contains($0) }) { return .sad }
        if Self.happyEventWords.contains(where: { lower.contains($0) }) { return .happy }
        return .none
    }

    /// Fuzzy match a word to a category keyword (dres→dress, jaket→jacket).
    private func fuzzyMatchCategory(word: String) -> String? {
        guard word.count >= minLengthForFuzzy else { return nil }
        var best: (match: String, distance: Int)?
        for keyword in Self.categoryKeywords {
            let d = Self.levenshtein(word, keyword)
            if d <= maxTypoDistance, best == nil || d < best!.distance {
                best = (keyword, d)
            }
        }
        return best?.match
    }

    /// Parses the raw query: normalize conversational phrasing, synonym expansion, colours, category, price, event; builds search string (training doc: always detect category/colour).
    func parse(query: String) -> ParsedSearch {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ParsedSearch(searchText: "", searchQueryCandidates: [], categoryOverride: nil, appliedColourNames: [], closestMatchHint: nil, spellingCorrectionHint: nil, priceMax: nil, detectedEvent: .none, sizeTerm: nil)
        }

        let normalized = normalizeConversational(trimmed)
        var expandedQuery = expandSynonyms(normalized.isEmpty ? trimmed : normalized)
        for (phrase, appColour) in Self.colourPhrases {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: phrase) + "\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                expandedQuery = regex.stringByReplacingMatches(in: expandedQuery, range: NSRange(expandedQuery.startIndex..., in: expandedQuery), withTemplate: appColour)
            }
        }
        let priceMax = extractPriceMax(from: expandedQuery)
        let detectedEvent = detectEvent(from: expandedQuery)

        let words = expandedQuery
            .components(separatedBy: .whitespaces)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }

        var appliedColours: [String] = []
        var appliedCategory: String? = nil
        var remainingWords: [String] = []
        var usedAlias: (requested: String, mapped: String)? = nil
        var spellingHint: (original: String, corrected: String)? = nil

        for word in words {
            let lower = word.lowercased()

            // 1) Colour alias
            if let mapped = Self.colourAliases[lower] {
                appliedColours.append(mapped)
                if usedAlias == nil { usedAlias = (word, mapped) }
                continue
            }

            // 2) Exact app colour
            if let match = Self.appColours.first(where: { $0.lowercased() == lower }) {
                appliedColours.append(match)
                remainingWords.append(word)
                continue
            }

            // 3) Fuzzy match colour (typos) — track correction for "Do you mean?"
            if lower.count >= minLengthForFuzzy, let match = fuzzyMatchColour(word: lower) {
                appliedColours.append(match)
                remainingWords.append(word)
                if spellingHint == nil && match.lowercased() != lower {
                    spellingHint = (word, match)
                }
                continue
            }

            // 4) Parent category — exact "women"/"men"/"boys"/"kids" etc. or possessive "women's"/"boys'" so "size 10 jeans women's" → category Women, search "jeans". Category words are not added to search text.
            if let cat = Self.parentCategories.first(where: { $0.lowercased() == lower && $0.lowercased() != "all" }) {
                appliedCategory = cat
                continue
            }
            if let cat = Self.parentCategoryFromWord(lower) {
                appliedCategory = cat
                continue
            }

            // 5) Category keyword
            if let match = fuzzyMatchCategory(word: lower) {
                remainingWords.append(match)
                if spellingHint == nil && match.lowercased() != lower {
                    let corrected = match.prefix(1).uppercased() + match.dropFirst()
                    spellingHint = (word, corrected)
                }
                continue
            }

            // 6) Subcategory
            if Self.subCategories.contains(where: { $0.lowercased() == lower }) {
                remainingWords.append(word)
                continue
            }

            remainingWords.append(word)
        }

        var searchParts = remainingWords
            .filter { !Self.searchStopwords.contains($0.lowercased()) }
        for c in appliedColours where !searchParts.contains(where: { $0.lowercased() == c.lowercased() }) {
            searchParts.append(c)
        }
        let extractedSize = extractSizeTerm(from: expandedQuery)
        if let sizeTerm = extractedSize {
            // Remove "size" and the size value from search parts so API gets e.g. "blue jeans" not "size 10 blue jeans" (backend text search returns no results for the latter).
            searchParts = searchParts.filter { $0.lowercased() != "size" && $0.lowercased() != sizeTerm }
        }
        let searchText = searchParts.joined(separator: " ")
        let candidates: [String] = {
            let terms = searchText.split(separator: " ").map(String.init).filter { !$0.isEmpty }
            if terms.count <= 1 { return searchText.isEmpty ? [] : [searchText] }
            return [searchText] + terms
        }()

        let hint: String?
        if let (req, mapped) = usedAlias, !appliedColours.isEmpty {
            hint = "Showing results closest to \"\(req)\" (\(mapped))"
        } else {
            hint = nil
        }

        return ParsedSearch(
            searchText: searchText,
            searchQueryCandidates: candidates,
            categoryOverride: appliedCategory,
            appliedColourNames: appliedColours,
            closestMatchHint: hint,
            spellingCorrectionHint: spellingHint,
            priceMax: priceMax,
            detectedEvent: detectedEvent,
            sizeTerm: extractedSize
        )
    }

    // MARK: - Realistic response sets (Batch 1: 20 query types × 5 responses)

    /// Response sets for contextual replies (Prelura AI Training Dataset — Realistic User Queries Batch 1).
    private static let responseBatch1: [(name: String, responses: [String])] = [
        ("birthday_party", [
            "Happy birthday! Let's find some great green dresses for your celebration.",
            "That sounds fun! Here are some green dresses that could work perfectly for a birthday party.",
            "Let's explore some green dress options for your birthday.",
            "Here are some green dresses that might be great for a birthday outfit.",
            "I'll show you some green dresses that could be perfect for celebrating."
        ]),
        ("boots_under_price", [
            "Here are some black boots under £50 you might like.",
            "These black boots match your budget.",
            "Let's explore some affordable black boot options.",
            "I've found some black boots within your price range.",
            "Here are some budget-friendly black boots."
        ]),
        ("lighter_than_navy", [
            "Let's explore some shades lighter than navy, like cobalt or royal blue.",
            "Here are some blue options slightly lighter than navy.",
            "You might like these bright navy and royal blue items.",
            "These items sit between navy and bright blue.",
            "Here are some lighter blue pieces close to navy."
        ]),
        ("comfy_travel", [
            "Here are some comfortable hoodies that could be great for travel.",
            "Let's find a cosy hoodie perfect for travelling.",
            "These relaxed hoodies might be ideal for your trip.",
            "Here are some hoodies designed for comfort.",
            "You might like these soft travel-friendly hoodies."
        ]),
        ("vintage_denim", [
            "Here are some vintage denim jackets you might like.",
            "Let's explore some retro denim jacket styles.",
            "These jackets have a vintage denim look.",
            "Here are some classic denim jackets.",
            "You might like these vintage-inspired denim jackets."
        ]),
        ("night_out_dress", [
            "Here are some short black dresses perfect for a night out.",
            "Let's find a stylish black dress for your night out.",
            "These short black dresses could work well.",
            "You might like these sleek black dress options.",
            "Here are some great night-out dresses."
        ]),
        ("everyday_trainers", [
            "Here are some white trainers great for everyday use.",
            "Let's explore some versatile white trainers.",
            "These white trainers are perfect for daily wear.",
            "You might like these comfortable white sneakers.",
            "Here are some casual white trainer options.",
            "Here are some white trainers under £40.",
            "Let's explore some budget-friendly white trainer options.",
            "These trainers stay within your price range.",
            "You might like these affordable white sneakers.",
            "Here are some everyday trainers under £40."
        ]),
        ("beige_minimalist", [
            "Here are some minimalist beige pieces.",
            "Let's explore some clean beige styles.",
            "These neutral beige items might match that look.",
            "You might like these simple beige designs.",
            "Here are some understated beige options."
        ]),
        ("oversized_hoodies", [
            "Here are some oversized hoodies you might like.",
            "Let's explore some relaxed-fit hoodies.",
            "These hoodies have an oversized style.",
            "You might like these baggy hoodie options.",
            "Here are some loose-fit hoodies.",
            "Here are some oversized hoodies with a streetwear vibe.",
            "Let's explore some relaxed streetwear hoodie styles.",
            "These hoodies have an oversized streetwear look.",
            "You might like these baggy hoodie designs.",
            "Here are some casual streetwear hoodies.",
            "Here are some comfy oversized hoodies.",
            "Let's explore some relaxed hoodie styles.",
            "These hoodies focus on comfort and fit.",
            "You might like these loose hoodie options.",
            "Here are some cosy hoodie picks."
        ]),
        ("festival_colourful", [
            "Let's find some colourful outfits perfect for a festival.",
            "Here are some vibrant pieces you might like.",
            "These colourful items could be great for a festival.",
            "You might enjoy these bright festival outfits.",
            "Here are some fun and colourful styles."
        ]),
        ("jeans_not_skinny", [
            "Here are some relaxed-fit blue jeans.",
            "Let's explore some straight-leg denim options.",
            "These looser jeans might suit you.",
            "You might like these wide-leg jeans.",
            "Here are some comfortable denim styles."
        ]),
        ("winter_coat", [
            "Here are some warm coats perfect for winter.",
            "Let's explore some winter coat options.",
            "These coats could keep you warm.",
            "You might like these thick winter jackets.",
            "Here are some cosy outerwear choices.",
            "Here are some beige winter coats.",
            "Let's explore some warm neutral coats.",
            "These coats could work well for winter.",
            "You might like these cosy beige styles.",
            "Here are some elegant coats."
        ]),
        ("leather_jackets", [
            "Here are some leather jackets you might like.",
            "Let's explore some leather jacket styles.",
            "These jackets have a leather finish.",
            "You might like these biker-style jackets.",
            "Here are some leather outerwear options."
        ]),
        ("dresses_under_price", [
            "Here are some dresses under £30.",
            "Let's explore some budget-friendly dresses.",
            "These dresses fit within your price range.",
            "You might like these affordable styles.",
            "Here are some low-cost dress options."
        ]),
        ("party_dress", [
            "Here are some red dresses perfect for a party.",
            "Let's explore some bold red dress options.",
            "These red dresses could be great for a party.",
            "You might like these vibrant red styles.",
            "Here are some festive red dresses.",
            "Here are some red dresses perfect for a party.",
            "Let's explore some bold party dress options.",
            "These dresses could work well for a party.",
            "You might like these vibrant red styles.",
            "Here are some festive dress options."
        ]),
        ("green_hoodies", [
            "Here are some green hoodies you might like.",
            "Let's explore some green hoodie styles.",
            "These hoodies come in green shades.",
            "You might like these casual green hoodies.",
            "Here are some comfortable green hoodie options.",
            "Here are some dark green hoodies that stay within a lower budget.",
            "Let's explore some affordable dark green hoodies.",
            "These green hoodies might match what you're looking for.",
            "I've found some budget-friendly dark green hoodie options.",
            "Here are some green hoodies that shouldn't break the bank."
        ]),
        ("wedding_classy", [
            "Let's explore some elegant wedding outfit options.",
            "Here are some classy styles that might suit a wedding.",
            "These outfits could work well for a wedding.",
            "You might like these refined pieces.",
            "Here are some sophisticated options."
        ]),
        ("yellow_sweaters", [
            "Here are some yellow sweaters.",
            "Let's explore some bright sweater options.",
            "These sweaters come in yellow tones.",
            "You might like these warm yellow knits.",
            "Here are some colourful sweater options."
        ]),
        ("casual_everyday_jacket", [
            "Here are some casual jackets you might like.",
            "Let's explore some everyday jacket styles.",
            "These jackets are great for daily wear.",
            "You might like these relaxed outerwear options.",
            "Here are some comfortable jackets."
        ]),
        ("stylish_cheap", [
            "Let's explore some stylish budget options.",
            "Here are some affordable fashion pieces.",
            "These items combine style and value.",
            "You might like these trendy affordable picks.",
            "Here are some stylish items within a lower budget.",
            "Let's explore some stylish pieces that are still budget-friendly.",
            "Here are some affordable options that could work for dinner.",
            "These items combine elegance and value.",
            "You might like these classy yet affordable styles.",
            "Here are some stylish pieces within a lower price range.",
            "Let's explore some trendy pieces that are still affordable.",
            "Here are some fashionable budget options.",
            "These items combine style and value.",
            "You might like these trendy picks within a lower budget.",
            "Here are some affordable fashion pieces."
        ]),
        // Batch 2 (new query types)
        ("light_blue_jeans", [
            "Here are some light blue jeans you might like.",
            "Let's explore some lighter denim styles.",
            "These jeans come in light blue shades.",
            "You might like these faded blue denim options.",
            "Here are some casual light blue jeans."
        ]),
        ("yellow_scarf_winter", [
            "Here are some yellow scarves that could work well for winter.",
            "Let's explore some warm yellow scarf options.",
            "These yellow scarves might match what you're looking for.",
            "You might like these cosy winter scarves.",
            "Here are some bright scarf options."
        ]),
        ("between_blue_green", [
            "Let's explore colours between blue and green like teal or turquoise.",
            "Here are some teal and aqua coloured items.",
            "These pieces blend blue and green tones.",
            "You might like these turquoise styles.",
            "Here are some items in that colour range."
        ]),
        ("heels_under_price", [
            "Here are some red heels under £40.",
            "Let's explore some affordable red heel options.",
            "These heels match your budget.",
            "You might like these red shoe styles.",
            "Here are some budget-friendly heels."
        ]),
        ("holiday_light_dresses", [
            "Let's find some lightweight dresses perfect for a holiday.",
            "Here are some breezy dress options.",
            "These dresses might work well for warm weather.",
            "You might like these summer dresses.",
            "Here are some relaxed holiday dresses."
        ]),
        ("brown_leather_boots", [
            "Here are some brown leather boots you might like.",
            "Let's explore some leather boot styles.",
            "These boots come in brown leather.",
            "You might like these classic boot designs.",
            "Here are some stylish leather boots."
        ]),
        ("neutral_work", [
            "Let's explore some neutral outfits suitable for work.",
            "Here are some simple office-friendly pieces.",
            "These neutral styles might work well.",
            "You might like these professional outfits.",
            "Here are some understated workwear options."
        ]),
        ("black_handbags", [
            "Here are some black handbags you might like.",
            "Let's explore some stylish bag options.",
            "These handbags come in black.",
            "You might like these classic bag styles.",
            "Here are some everyday handbags."
        ]),
        ("trainers_gym", [
            "Here are some trainers that could work well for the gym.",
            "Let's explore some sporty trainer options.",
            "These shoes might be good for workouts.",
            "You might like these athletic trainers.",
            "Here are some comfortable gym shoes."
        ]),
        ("vintage_dresses", [
            "Here are some vintage-style dresses.",
            "Let's explore some retro dress options.",
            "These dresses have a vintage look.",
            "You might like these classic styles.",
            "Here are some timeless dresses."
        ]),
        ("muted_green_jacket", [
            "Here are some muted green jackets.",
            "Let's explore some darker green outerwear.",
            "These jackets have subtle green tones.",
            "You might like these olive green jackets.",
            "Here are some softer green options."
        ]),
        ("cheap_hoodies", [
            "Here are some budget-friendly hoodies.",
            "Let's explore some affordable hoodie options.",
            "These hoodies stay within a lower price range.",
            "You might like these casual hoodies.",
            "Here are some inexpensive styles."
        ]),
        ("pink_skirts", [
            "Here are some pink skirts you might like.",
            "Let's explore some skirt styles in pink.",
            "These skirts come in pink shades.",
            "You might like these colourful skirts.",
            "Here are some casual skirt options."
        ]),
        ("cute_date", [
            "Let's explore some cute outfit options.",
            "Here are some styles that might work well for a date.",
            "These outfits might match that vibe.",
            "You might like these flattering looks.",
            "Here are some stylish pieces."
        ]),
        ("grey_hoodies", [
            "Here are some grey hoodies.",
            "Let's explore some hoodie styles in grey.",
            "These hoodies come in grey tones.",
            "You might like these casual hoodies.",
            "Here are some relaxed hoodie options."
        ]),
        ("warm_stylish", [
            "Let's explore some warm and stylish pieces.",
            "Here are some cosy outfit options.",
            "These items combine comfort and style.",
            "You might like these winter-ready styles.",
            "Here are some warm fashion picks."
        ]),
        ("blue_jackets", [
            "Here are some blue jackets.",
            "Let's explore some jacket styles in blue.",
            "These jackets come in blue shades.",
            "You might like these casual jackets.",
            "Here are some outerwear options."
        ]),
        // Batch 3 (queries 21–40)
        ("olive_cargo_trousers", [
            "Here are some olive green cargo trousers you might like.",
            "Let's explore some cargo trousers in olive green.",
            "These trousers match the olive green cargo style.",
            "You might like these relaxed cargo trousers.",
            "Here are some casual olive green cargo options."
        ]),
        ("pastel_pink_cardigans", [
            "Here are some pastel pink cardigans you might like.",
            "Let's explore some soft pink cardigan styles.",
            "These cardigans come in pastel pink shades.",
            "You might like these light pink knitwear options.",
            "Here are some cosy pastel cardigans."
        ]),
        ("navy_blazer_work", [
            "Here are some navy blue blazers suitable for work.",
            "Let's explore some professional navy blazer options.",
            "These blazers could work well for office wear.",
            "You might like these classic navy styles.",
            "Here are some smart blazer options."
        ]),
        ("oversized_grey_sweaters", [
            "Here are some oversized grey sweaters you might like.",
            "Let's explore some relaxed grey knitwear.",
            "These sweaters have an oversized fit.",
            "You might like these cosy grey styles.",
            "Here are some comfortable oversized sweaters."
        ]),
        ("brown_suede_jackets", [
            "Here are some brown suede jackets you might like.",
            "Let's explore some suede outerwear options.",
            "These jackets come in brown suede.",
            "You might like these classic suede styles.",
            "Here are some stylish suede jackets."
        ]),
        ("dark_blue_skinny_jeans", [
            "Here are some dark blue skinny jeans you might like.",
            "Let's explore some fitted denim styles.",
            "These jeans come in dark blue shades.",
            "You might like these slim-fit denim options.",
            "Here are some classic skinny jeans."
        ]),
        ("cream_sweater_winter", [
            "Here are some cream knit sweaters perfect for winter.",
            "Let's explore some warm knitwear options.",
            "These sweaters come in cream tones.",
            "You might like these cosy winter knits.",
            "Here are some soft cream sweaters."
        ]),
        ("yellow_summer_dress", [
            "Here are some yellow summer dresses.",
            "Let's explore some bright summer styles.",
            "These dresses come in yellow shades.",
            "You might like these warm-weather dresses.",
            "Here are some light and colourful dress options."
        ]),
        ("muted_purple_hoodie", [
            "Here are some hoodies in muted purple tones.",
            "Let's explore some soft purple hoodie styles.",
            "These hoodies come in subtle purple shades.",
            "You might like these relaxed hoodie options.",
            "Here are some understated purple hoodies."
        ]),
        ("vintage_leather_bags", [
            "Here are some vintage brown leather bags.",
            "Let's explore some classic leather bag styles.",
            "These bags have a vintage leather look.",
            "You might like these timeless leather designs.",
            "Here are some retro-inspired handbags."
        ]),
        ("oversized_black_tees", [
            "Here are some oversized black t-shirts you might like.",
            "Let's explore some relaxed-fit black tees.",
            "These t-shirts have an oversized style.",
            "You might like these streetwear-style shirts.",
            "Here are some loose black t-shirts."
        ]),
        ("minimalist_white_shirts", [
            "Here are some minimalist white shirts.",
            "Let's explore some clean and simple shirt designs.",
            "These shirts follow a minimalist style.",
            "You might like these classic white shirts.",
            "Here are some understated shirt options."
        ]),
        ("green_dress_graduation", [
            "Congratulations on graduating! Let's find a great green dress.",
            "Here are some green dresses that could work for graduation.",
            "Let's explore some elegant green dress options.",
            "You might like these graduation-ready dresses.",
            "Here are some stylish green dresses."
        ]),
        ("light_grey_joggers", [
            "Here are some light grey joggers.",
            "Let's explore some comfortable jogger options.",
            "These joggers come in light grey shades.",
            "You might like these casual joggers.",
            "Here are some relaxed-fit joggers."
        ]),
        ("comfy_travel_generic", [
            "Let's explore some comfortable travel outfits.",
            "Here are some relaxed clothing options for travelling.",
            "These pieces focus on comfort.",
            "You might like these easygoing styles.",
            "Here are some comfy travel picks."
        ]),
        ("black_stylish_trainers", [
            "Here are some stylish black trainers.",
            "Let's explore some fashionable trainer options.",
            "These trainers combine style and comfort.",
            "You might like these sleek black sneakers.",
            "Here are some trendy trainer options."
        ]),
        ("vintage_denim_jeans", [
            "Here are some vintage denim jeans.",
            "Let's explore some retro denim styles.",
            "These jeans have a vintage look.",
            "You might like these classic denim options.",
            "Here are some old-school denim styles."
        ]),
        ("casual_weekend", [
            "Let's explore some casual weekend outfits.",
            "Here are some relaxed styles perfect for weekends.",
            "These pieces are great for everyday wear.",
            "You might like these comfortable outfits.",
            "Here are some easygoing clothing options."
        ]),
        // Batch 4 (queries 41–60)
        ("bold_colourful", [
            "Let's explore some bold and colourful fashion pieces.",
            "Here are some vibrant items you might like.",
            "These pieces feature bright colours and standout designs.",
            "You might enjoy these colourful styles.",
            "Here are some eye-catching outfits."
        ]),
        ("pastel_blue_hoodie", [
            "Here are some hoodies in pastel blue.",
            "Let's explore some soft blue hoodie styles.",
            "These hoodies come in light blue shades.",
            "You might like these relaxed pastel hoodies.",
            "Here are some cosy pastel blue options."
        ]),
        ("elegant_heels_wedding", [
            "Here are some elegant heels suitable for a wedding.",
            "Let's explore some sophisticated shoe options.",
            "These heels could work well for a wedding outfit.",
            "You might like these classy footwear styles.",
            "Here are some stylish wedding heels."
        ]),
        ("smart_jacket_work", [
            "Here are some smart jackets suitable for work.",
            "Let's explore some professional outerwear.",
            "These jackets might work well for the office.",
            "You might like these tailored jacket styles.",
            "Here are some polished jacket options."
        ]),
        ("cosy_cardigans_winter", [
            "Here are some cosy winter cardigans.",
            "Let's explore some warm knitwear.",
            "These cardigans could keep you warm in winter.",
            "You might like these comfortable knit styles.",
            "Here are some soft cardigan options."
        ]),
        ("neutral_simple", [
            "Let's explore some neutral and minimalist styles.",
            "Here are some simple clothing options.",
            "These pieces focus on clean and neutral tones.",
            "You might like these understated outfits.",
            "Here are some minimalist wardrobe pieces."
        ]),
        ("oversized_flannel_shirts", [
            "Here are some oversized flannel shirts.",
            "Let's explore some relaxed flannel styles.",
            "These shirts feature an oversized fit.",
            "You might like these casual flannel options.",
            "Here are some cosy flannel shirts."
        ]),
        ("light_brown_boots", [
            "Here are some light brown boots.",
            "Let's explore some brown boot styles.",
            "These boots come in lighter brown shades.",
            "You might like these classic boot options.",
            "Here are some casual brown boots."
        ]),
        ("black_skirts_work", [
            "Here are some black skirts suitable for work.",
            "Let's explore some office-friendly skirt styles.",
            "These skirts could work well for professional outfits.",
            "You might like these classic skirt options.",
            "Here are some simple black skirts."
        ]),
        ("lightweight_summer_jacket", [
            "Here are some lightweight jackets perfect for summer.",
            "Let's explore some breathable outerwear.",
            "These jackets could work well for warm weather.",
            "You might like these casual summer styles.",
            "Here are some light jacket options."
        ]),
        ("blue_hoodies_everyday", [
            "Here are some blue hoodies for everyday wear.",
            "Let's explore some casual hoodie options.",
            "These hoodies come in blue shades.",
            "You might like these comfortable styles.",
            "Here are some relaxed hoodie picks."
        ]),
        ("stylish_handbag_under_price", [
            "Here are some stylish handbags under £50.",
            "Let's explore some fashionable bag options within your budget.",
            "These handbags stay under £50.",
            "You might like these affordable bag styles.",
            "Here are some budget-friendly handbags."
        ]),
        ("beige_trousers_office", [
            "Here are some beige trousers suitable for office wear.",
            "Let's explore some professional trouser styles.",
            "These trousers could work well for work outfits.",
            "You might like these neutral trouser options.",
            "Here are some office-ready trousers."
        ]),
        ("vintage_bomber_jacket", [
            "Here are some vintage bomber jackets.",
            "Let's explore some retro bomber styles.",
            "These jackets have a vintage bomber look.",
            "You might like these classic bomber designs.",
            "Here are some stylish bomber jackets."
        ]),
        ("pastel_sweaters", [
            "Here are some sweaters in pastel colours.",
            "Let's explore some soft-toned knitwear.",
            "These sweaters feature pastel shades.",
            "You might like these light coloured sweaters.",
            "Here are some gentle pastel styles."
        ]),
        ("lightweight_scarf_spring", [
            "Here are some lightweight scarves perfect for spring.",
            "Let's explore some breathable scarf styles.",
            "These scarves are ideal for warmer weather.",
            "You might like these soft scarf options.",
            "Here are some spring-ready scarves."
        ]),
        ("stylish_boots_winter", [
            "Here are some stylish boots suitable for winter.",
            "Let's explore some winter boot options.",
            "These boots combine warmth and style.",
            "You might like these fashionable winter boots.",
            "Here are some cosy boot picks."
        ])
    ]

    /// Warm, friendly lead-in phrases for successful results (picked at random so the AI feels personable).
    private static let warmLeadInPhrases: [String] = [
        "I can certainly help you with that.",
        "Of course!",
        "Let me have a look…",
        "Happy to help!",
        "I'd be glad to.",
        "Sure thing!",
        "Absolutely!",
        "Let me find something for you.",
        "I'm on it!",
        "No problem at all.",
        "Consider it done.",
        "I've got you covered.",
        "Here we go!",
        "Let me see what I can find.",
        "I'd love to help.",
        "Of course I can!",
        "Glad to help!",
        "One moment…",
        "Coming right up!",
        "I'll see what's available."
    ]

    /// Picks the best-matching response set from Batch 1, 2, 3 & 4, or falls back to event-based generic replies.
    private func selectResponseSet(parsed: ParsedSearch, query: String?) -> [String]? {
        let q = (query ?? "").lowercased()
        let search = parsed.searchText.lowercased()
        let colours = Set(parsed.appliedColourNames.map { $0.lowercased() })
        let hasPrice = parsed.priceMax != nil
        let isHappy = parsed.detectedEvent == .happy

        if (q.contains("bold") && (q.contains("colourful") || q.contains("colorful"))) || (q.contains("eye-catching") && q.contains("colourful")) {
            return Self.responseBatch1.first(where: { $0.name == "bold_colourful" })?.responses
        }
        if (q.contains("pastel") && colours.contains("blue")) && (search.contains("hoodie") || q.contains("hoodies")) {
            return Self.responseBatch1.first(where: { $0.name == "pastel_blue_hoodie" })?.responses
        }
        if (q.contains("elegant") || search.contains("elegant")) && (search.contains("heel") || q.contains("heels")) && (q.contains("wedding") || search.contains("wedding")) {
            return Self.responseBatch1.first(where: { $0.name == "elegant_heels_wedding" })?.responses
        }
        if (q.contains("smart") || search.contains("smart")) && (search.contains("jacket") || q.contains("jacket")) && (q.contains("work") || search.contains("work") || q.contains("office")) {
            return Self.responseBatch1.first(where: { $0.name == "smart_jacket_work" })?.responses
        }
        if (q.contains("cosy") || q.contains("cozy")) && (search.contains("cardigan") || q.contains("cardigans")) && (q.contains("winter") || search.contains("winter")) {
            return Self.responseBatch1.first(where: { $0.name == "cosy_cardigans_winter" })?.responses
        }
        if (q.contains("neutral") && q.contains("simple")) || (search.contains("neutral") && q.contains("simple")) {
            return Self.responseBatch1.first(where: { $0.name == "neutral_simple" })?.responses
        }
        if (search.contains("oversized") || q.contains("oversized")) && (q.contains("flannel") || search.contains("flannel")) && (search.contains("shirt") || q.contains("shirts")) {
            return Self.responseBatch1.first(where: { $0.name == "oversized_flannel_shirts" })?.responses
        }
        if (colours.contains("brown") && (q.contains("light") || q.contains("lighter"))) && (search.contains("boot") || q.contains("boots")) {
            return Self.responseBatch1.first(where: { $0.name == "light_brown_boots" })?.responses
        }
        if colours.contains("black") && (search.contains("skirt") || q.contains("skirts")) && (q.contains("work") || search.contains("work") || q.contains("office")) {
            return Self.responseBatch1.first(where: { $0.name == "black_skirts_work" })?.responses
        }
        if (q.contains("lightweight") || search.contains("lightweight")) && (q.contains("summer") || search.contains("summer")) && (search.contains("jacket") || q.contains("jacket")) {
            return Self.responseBatch1.first(where: { $0.name == "lightweight_summer_jacket" })?.responses
        }
        if colours.contains("blue") && (search.contains("hoodie") || q.contains("hoodies")) && (q.contains("everyday") || q.contains("every day")) {
            return Self.responseBatch1.first(where: { $0.name == "blue_hoodies_everyday" })?.responses
        }
        if (q.contains("stylish") || q.contains("fashionable")) && (search.contains("handbag") || search.contains("bag") || q.contains("handbag")) && hasPrice {
            return Self.responseBatch1.first(where: { $0.name == "stylish_handbag_under_price" })?.responses
        }
        if colours.contains("beige") && (search.contains("trouser") || q.contains("trousers")) && (q.contains("office") || search.contains("office") || q.contains("work")) {
            return Self.responseBatch1.first(where: { $0.name == "beige_trousers_office" })?.responses
        }
        if (search.contains("vintage") || q.contains("vintage")) && (q.contains("bomber") || search.contains("bomber")) && (search.contains("jacket") || q.contains("jacket")) {
            return Self.responseBatch1.first(where: { $0.name == "vintage_bomber_jacket" })?.responses
        }
        if (q.contains("pastel") || search.contains("pastel")) && (search.contains("sweater") || search.contains("jumper") || q.contains("sweaters")) {
            return Self.responseBatch1.first(where: { $0.name == "pastel_sweaters" })?.responses
        }
        if (q.contains("lightweight") || search.contains("lightweight")) && (search.contains("scarf") || q.contains("scarves")) && (q.contains("spring") || search.contains("spring")) {
            return Self.responseBatch1.first(where: { $0.name == "lightweight_scarf_spring" })?.responses
        }
        if (q.contains("stylish") || search.contains("stylish")) && (search.contains("boot") || q.contains("boots")) && (q.contains("winter") || search.contains("winter")) {
            return Self.responseBatch1.first(where: { $0.name == "stylish_boots_winter" })?.responses
        }
        if (q.contains("graduation") || search.contains("graduation")) && colours.contains("green") && (search.contains("dress") || q.contains("dress")) {
            return Self.responseBatch1.first(where: { $0.name == "green_dress_graduation" })?.responses
        }
        if (search.contains("vintage") || q.contains("vintage")) && (search.contains("jeans") || q.contains("jeans")) && !(search.contains("jacket") || q.contains("jacket")) {
            return Self.responseBatch1.first(where: { $0.name == "vintage_denim_jeans" })?.responses
        }
        if (q.contains("olive") || (colours.contains("green") && q.contains("cargo"))) && (search.contains("trouser") || search.contains("cargo") || q.contains("cargo") || q.contains("trousers")) {
            return Self.responseBatch1.first(where: { $0.name == "olive_cargo_trousers" })?.responses
        }
        if (q.contains("pastel") && colours.contains("pink")) && (q.contains("cardigan") || search.contains("cardigan")) {
            return Self.responseBatch1.first(where: { $0.name == "pastel_pink_cardigans" })?.responses
        }
        if colours.contains("navy") && (q.contains("blazer") || search.contains("blazer")) && (q.contains("work") || search.contains("work")) {
            return Self.responseBatch1.first(where: { $0.name == "navy_blazer_work" })?.responses
        }
        if (search.contains("oversized") || q.contains("oversized")) && colours.contains("grey") && (search.contains("sweater") || search.contains("jumper") || q.contains("sweaters")) {
            return Self.responseBatch1.first(where: { $0.name == "oversized_grey_sweaters" })?.responses
        }
        if colours.contains("brown") && (q.contains("suede") || search.contains("suede")) && (search.contains("jacket") || q.contains("jackets")) {
            return Self.responseBatch1.first(where: { $0.name == "brown_suede_jackets" })?.responses
        }
        if (colours.contains("navy") || (colours.contains("blue") && q.contains("dark"))) && (q.contains("skinny") || search.contains("skinny")) && (search.contains("jeans") || q.contains("jeans")) {
            return Self.responseBatch1.first(where: { $0.name == "dark_blue_skinny_jeans" })?.responses
        }
        if (colours.contains("white") || q.contains("cream")) && (search.contains("sweater") || search.contains("jumper") || q.contains("sweater")) && (q.contains("winter") || search.contains("winter")) {
            return Self.responseBatch1.first(where: { $0.name == "cream_sweater_winter" })?.responses
        }
        if colours.contains("yellow") && (q.contains("summer") || search.contains("summer")) && (search.contains("dress") || q.contains("dresses")) {
            return Self.responseBatch1.first(where: { $0.name == "yellow_summer_dress" })?.responses
        }
        if colours.contains("purple") && (q.contains("muted") || q.contains("subtle")) && (search.contains("hoodie") || q.contains("hoodies")) {
            return Self.responseBatch1.first(where: { $0.name == "muted_purple_hoodie" })?.responses
        }
        if (search.contains("vintage") || q.contains("vintage")) && (search.contains("leather") || q.contains("leather")) && (search.contains("bag") || search.contains("handbag") || q.contains("bags")) {
            return Self.responseBatch1.first(where: { $0.name == "vintage_leather_bags" })?.responses
        }
        if (search.contains("oversized") || q.contains("oversized")) && colours.contains("black") && (search.contains("tee") || search.contains("tshirt") || q.contains("t-shirt") || q.contains("t-shirts")) {
            return Self.responseBatch1.first(where: { $0.name == "oversized_black_tees" })?.responses
        }
        if (q.contains("minimalist") || search.contains("minimalist")) && colours.contains("white") && (search.contains("shirt") || q.contains("shirts")) {
            return Self.responseBatch1.first(where: { $0.name == "minimalist_white_shirts" })?.responses
        }
        if (search.contains("jogger") || q.contains("joggers")) && (colours.contains("grey") || q.contains("light grey")) {
            return Self.responseBatch1.first(where: { $0.name == "light_grey_joggers" })?.responses
        }
        if (q.contains("comfy") || q.contains("comfortable")) && (q.contains("travelling") || q.contains("travel")) && !(search.contains("hoodie") || q.contains("hoodie")) {
            return Self.responseBatch1.first(where: { $0.name == "comfy_travel_generic" })?.responses
        }
        if colours.contains("black") && (search.contains("trainer") || search.contains("sneaker") || q.contains("trainers")) && (q.contains("stylish") || q.contains("fashionable")) {
            return Self.responseBatch1.first(where: { $0.name == "black_stylish_trainers" })?.responses
        }
        if (q.contains("weekend") || search.contains("weekend")) && (q.contains("casual") || search.contains("casual")) {
            return Self.responseBatch1.first(where: { $0.name == "casual_weekend" })?.responses
        }
        if (q.contains("between") && (q.contains("blue") && q.contains("green"))) || (search.contains("teal") && colours.contains("blue")) {
            return Self.responseBatch1.first(where: { $0.name == "between_blue_green" })?.responses
        }
        if (q.contains("light blue") || (colours.contains("blue") && q.contains("light"))) && (search.contains("jeans") || q.contains("jeans")) {
            return Self.responseBatch1.first(where: { $0.name == "light_blue_jeans" })?.responses
        }
        if colours.contains("yellow") && (search.contains("scarf") || q.contains("scarf")) && (q.contains("winter") || search.contains("winter")) {
            return Self.responseBatch1.first(where: { $0.name == "yellow_scarf_winter" })?.responses
        }
        if (search.contains("heel") || q.contains("heels")) && hasPrice {
            return Self.responseBatch1.first(where: { $0.name == "heels_under_price" })?.responses
        }
        if (q.contains("holiday") || q.contains("vacation")) && (search.contains("dress") || q.contains("dresses")) {
            return Self.responseBatch1.first(where: { $0.name == "holiday_light_dresses" })?.responses
        }
        if colours.contains("brown") && (search.contains("leather") || q.contains("leather")) && (search.contains("boot") || q.contains("boots")) {
            return Self.responseBatch1.first(where: { $0.name == "brown_leather_boots" })?.responses
        }
        if (q.contains("neutral") || search.contains("neutral")) && (q.contains("work") || search.contains("work")) {
            return Self.responseBatch1.first(where: { $0.name == "neutral_work" })?.responses
        }
        if colours.contains("black") && (search.contains("handbag") || search.contains("bag") || q.contains("handbag") || q.contains("handbags")) {
            return Self.responseBatch1.first(where: { $0.name == "black_handbags" })?.responses
        }
        if (search.contains("trainer") || search.contains("sneaker") || q.contains("trainers")) && (q.contains("gym") || search.contains("gym")) {
            return Self.responseBatch1.first(where: { $0.name == "trainers_gym" })?.responses
        }
        if (search.contains("vintage") || q.contains("vintage")) && (search.contains("dress") || q.contains("dresses")) {
            return Self.responseBatch1.first(where: { $0.name == "vintage_dresses" })?.responses
        }
        if colours.contains("green") && (search.contains("jacket") || q.contains("jacket")) && (q.contains("not too bright") || q.contains("muted") || q.contains("subtle")) {
            return Self.responseBatch1.first(where: { $0.name == "muted_green_jacket" })?.responses
        }
        if (search.contains("hoodie") || q.contains("hoodies")) && (q.contains("cheap") || (hasPrice && !colours.contains("green"))) {
            if colours.contains("grey") { return Self.responseBatch1.first(where: { $0.name == "grey_hoodies" })?.responses }
            return Self.responseBatch1.first(where: { $0.name == "cheap_hoodies" })?.responses
        }
        if colours.contains("pink") && (search.contains("skirt") || q.contains("skirts")) {
            return Self.responseBatch1.first(where: { $0.name == "pink_skirts" })?.responses
        }
        if (q.contains("cute") || q.contains("flattering")) && (q.contains("date") || search.contains("date")) {
            return Self.responseBatch1.first(where: { $0.name == "cute_date" })?.responses
        }
        if colours.contains("grey") && (search.contains("hoodie") || q.contains("hoodies")) {
            return Self.responseBatch1.first(where: { $0.name == "grey_hoodies" })?.responses
        }
        if (q.contains("warm") && q.contains("stylish")) || (search.contains("warm") && search.contains("stylish")) {
            return Self.responseBatch1.first(where: { $0.name == "warm_stylish" })?.responses
        }
        if colours.contains("blue") && (search.contains("jacket") || q.contains("jackets")) && !search.contains("leather") {
            return Self.responseBatch1.first(where: { $0.name == "blue_jackets" })?.responses
        }
        if q.contains("birthday") && (search.contains("dress") || search.contains("green")) && isHappy {
            return Self.responseBatch1.first(where: { $0.name == "birthday_party" })?.responses
        }
        if (search.contains("boot") || q.contains("boots")) && hasPrice {
            return Self.responseBatch1.first(where: { $0.name == "boots_under_price" })?.responses
        }
        if q.contains("lighter than") || q.contains("lighter than navy") || (q.contains("lighter") && colours.contains("navy")) {
            return Self.responseBatch1.first(where: { $0.name == "lighter_than_navy" })?.responses
        }
        if (q.contains("comfy") || q.contains("travelling") || q.contains("travel")) && (search.contains("hoodie") || q.contains("hoodie")) {
            return Self.responseBatch1.first(where: { $0.name == "comfy_travel" })?.responses
        }
        if (search.contains("vintage") || q.contains("vintage")) && (search.contains("denim") || search.contains("jacket")) {
            return Self.responseBatch1.first(where: { $0.name == "vintage_denim" })?.responses
        }
        if (q.contains("night out") || q.contains("night out")) && (search.contains("dress") || colours.contains("black")) {
            return Self.responseBatch1.first(where: { $0.name == "night_out_dress" })?.responses
        }
        if (search.contains("trainer") || search.contains("sneaker") || q.contains("trainers")) && (q.contains("everyday") || q.contains("daily") || (hasPrice && colours.contains("white"))) {
            return Self.responseBatch1.first(where: { $0.name == "everyday_trainers" })?.responses
        }
        if colours.contains("beige") && (q.contains("minimalist") || search.contains("minimalist")) {
            return Self.responseBatch1.first(where: { $0.name == "beige_minimalist" })?.responses
        }
        if (search.contains("oversized") || q.contains("oversized")) && (search.contains("hoodie") || q.contains("hoodies")) {
            return Self.responseBatch1.first(where: { $0.name == "oversized_hoodies" })?.responses
        }
        if (q.contains("festival") || isHappy) && (q.contains("colourful") || q.contains("colorful") || search.contains("colourful")) {
            return Self.responseBatch1.first(where: { $0.name == "festival_colourful" })?.responses
        }
        if (search.contains("jeans") || q.contains("jeans")) && (q.contains("not skinny") || q.contains("but not")) {
            return Self.responseBatch1.first(where: { $0.name == "jeans_not_skinny" })?.responses
        }
        if (search.contains("coat") || search.contains("jacket") || q.contains("coat")) && (q.contains("winter") || search.contains("winter")) {
            return Self.responseBatch1.first(where: { $0.name == "winter_coat" })?.responses
        }
        if (search.contains("leather") || q.contains("leather")) && (search.contains("jacket") || q.contains("jackets")) {
            return Self.responseBatch1.first(where: { $0.name == "leather_jackets" })?.responses
        }
        if search.contains("dress") && hasPrice && !search.contains("boot") {
            return Self.responseBatch1.first(where: { $0.name == "dresses_under_price" })?.responses
        }
        if colours.contains("red") && (search.contains("dress") || q.contains("dress")) && (q.contains("party") || isHappy) {
            return Self.responseBatch1.first(where: { $0.name == "party_dress" })?.responses
        }
        if colours.contains("green") && (search.contains("hoodie") || q.contains("hoodies")) {
            return Self.responseBatch1.first(where: { $0.name == "green_hoodies" })?.responses
        }
        if (q.contains("wedding") || search.contains("wedding")) && (q.contains("classy") || q.contains("elegant") || search.contains("classy")) {
            return Self.responseBatch1.first(where: { $0.name == "wedding_classy" })?.responses
        }
        if colours.contains("yellow") && (search.contains("sweater") || search.contains("jumper") || q.contains("sweaters")) {
            return Self.responseBatch1.first(where: { $0.name == "yellow_sweaters" })?.responses
        }
        if (search.contains("casual") || q.contains("casual")) && (search.contains("jacket") || q.contains("jackets")) && (q.contains("everyday") || q.contains("daily")) {
            return Self.responseBatch1.first(where: { $0.name == "casual_everyday_jacket" })?.responses
        }
        if (q.contains("stylish") || q.contains("style") || q.contains("classy")) && (q.contains("cheap") || hasPrice) {
            return Self.responseBatch1.first(where: { $0.name == "stylish_cheap" })?.responses
        }
        return nil
    }

    /// Possible reply strings when we have results. Uses Batch 1 response sets when matched, else event-aware generic replies. When a typo was corrected, prepends "Do you mean 'X'?".
    /// Warm, helpful no-results messages so the AI still feels trained when nothing matches.
    private static let noResultsPhrases: [String] = [
        "I couldn't find anything matching that right now. Try different colours or categories, or a simpler search like just the item type.",
        "Nothing came up for that. I'd try searching for just the item (e.g. dress or jacket) or a different colour.",
        "No matches at the moment. Try dropping the colour and search for the item, or switch the colour or style.",
        "I had a look but didn't find that exact combo. Try a different colour or just the category — we might have something close.",
        "Nothing matching that right now. Try a simpler search or different options; I'm here to help.",
        "I couldn't find that combination. Try searching for just the item type, or change the colour or filters.",
        "No results for that search. Try different colours or categories, or a broader term.",
        "I looked but didn't find anything for that. Try the item on its own or another colour — new stuff is added often."
    ]

    /// Reply when the main search returned no items. Picks a warm, helpful no-results message.
    func replyForNoResults() -> String {
        (Self.noResultsPhrases.randomElement() ?? Self.noResultsPhrases[0])
    }

    /// True if the query is only a greeting (e.g. "Hello") — show a friendly prompt instead of search.
    /// Normalizes user input for salutation/social matching: lowercase, trim, collapse whitespace, straight apostrophe, strip punctuation so "Hi, how are you?" matches "hi how are you".
    private func normalizedForSalutation(_ query: String) -> String {
        var q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        q = q.replacingOccurrences(of: "\u{2019}", with: "'") // curly apostrophe → straight
        let punctuation = CharacterSet(charactersIn: ",.!?")
        q = q.unicodeScalars.filter { !punctuation.contains($0) }.map(String.init).joined()
        q = q.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        return q
    }

    /// True if the query is only a greeting/salutation or a social question (e.g. "hi", "good morning", "Hi Lenny", "Hey there Lenny"). Matches 100 salutations + 100 social phrases; also treats any message that contains "lenny" and is otherwise just a greeting (or nothing) as a greeting so "Hi Lenny", "Hey Lenny", "Hello Lenny" etc. get a greeting reply.
    func isGreetingOnly(_ query: String) -> Bool {
        let normalized = normalizedForSalutation(query)
        guard !normalized.isEmpty else { return false }
        if Self.salutations.contains(normalized) || Self.socialGreetingPhrases.contains(normalized) {
            return true
        }
        // User addressed the AI by name: "Hi Lenny", "Hey Lenny", "Hello Lenny", "Hey there Lenny", etc.
        guard normalized.contains("lenny") else { return false }
        let withoutLenny = normalized
            .replacingOccurrences(of: "lenny", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if withoutLenny.isEmpty { return true }
        return Self.salutations.contains(withoutLenny) || Self.socialGreetingPhrases.contains(withoutLenny)
    }

    /// Greeting replies when user says "hi", "hello", or social questions. Lenny always identifies himself and welcomes to Prelura. Used for both salutations and social Q&A.
    private static let greetingReplies: [String] = [
        "Hi, I'm Lenny — welcome to Prelura. How can I help?",
        "Hello! I'm Lenny, welcome to Prelura. What can I help you find today?",
        "Hey there! Lenny here — welcome to Prelura. How can I help you?",
        "Hi! I'm Lenny, welcome to Prelura. How can I help?",
        "Hello! Welcome to Prelura — I'm Lenny. How can I help you today?",
        "Hey! I'm Lenny, welcome to Prelura. What are you looking for?",
        "Hi there! Lenny here. Welcome to Prelura — how can I help?",
        "Hello! I'm Lenny, welcome to Prelura. How can I help you find something?",
        "Hi! Welcome to Prelura. I'm Lenny — how can I help?",
        "Hey there! I'm Lenny, welcome to Prelura. What can I help you with?",
        "Hello! Welcome to the chat — I'm Lenny, and I'm here to help with whatever you need. Just type what you're looking for to get started.",
        "Hey there! I'm Lenny. Great to have you here. Tell me what you're after — a colour and item like leather jacket or denim jeans works a treat.",
        "Hi! Lenny here. Welcome in. I'm here to help you find something lovely — try typing something like black jacket or green dress.",
        "Hello! I'm Lenny, and I'm really here to assist you. You can start by typing what you're looking for — for example, striped top or floral dress.",
        "Hey! Welcome to the chat. I'm Lenny and I'm here to help you find whatever you need. Just drop a message — try a colour and item like navy blazer or pink skirt.",
        "Hi there! Lenny at your service. Good to see you. Type anything you're after — dresses, jackets, shoes — or try wool coat or ankle boots.",
        "Hello! I'm Lenny. Welcome. I'm here to assist you with whatever you need. You can start by typing — e.g. black jacket or white trainers.",
        "Hey! Welcome — I'm Lenny. I'm here to help you shop. Just type what you're looking for to get started; something like green hoodie or beige coat works.",
        "Hi! Lenny here — welcome to the chat. I'm here to help with whatever you need. Type a colour and item, like summer dress or sandals, and we'll go from there.",
        "Hello! Welcome. I'm Lenny and I'm here to assist you. You can start by typing what you'd like to find — try knit jumper or tailored trousers.",
        "Hey there! I'm Lenny. Glad you're here. I'm here to help you find something — just type what you're looking for. Try black jacket or green dress.",
        "Hi! Welcome to the chat. I'm Lenny, and I'm here to help with whatever you need. Start by typing — for example, navy blazer or pink skirt.",
        "Hello! I'm Lenny — welcome. I'm here to assist you. You can type what you're looking for; try a colour and item like trench coat or loafers.",
        "Hey! Lenny here. Welcome in. I'm here to help you find whatever you need. Just type to get started — e.g. white trainers or black dress.",
        "Hi there! Welcome. I'm Lenny and I'm here to assist you. Type what you're after to get started; something like blouse or heels.",
        "Hello! I'm Lenny. Good to have you. I'm here to help with whatever you need. You can start by typing — try green hoodie or beige coat.",
        "Hey! Welcome to the chat. I'm Lenny, and I'm here to help you shop. Just type what you're looking for — like cardigan or sneakers.",
        "Hi! Lenny at your service. Welcome. I'm here to assist you with whatever you need. Type a message to get started; try black jacket or green dress.",
        "Hello! I'm Lenny — welcome. I'm here to help you find something. You can start by typing; for example, navy blazer or pink skirt.",
        "Hey there! Welcome. I'm Lenny and I'm here to help. Just type what you're looking for to get started — maxi dress, espadrilles, whatever you like.",
        "Hi! I'm Lenny. Welcome to the chat. I'm here to assist you with whatever you need. Start by typing — e.g. linen shirt or chinos.",
        "Hello! Lenny here. Good to see you. I'm here to help you find whatever you need. Type what you're after; try a colour and item like blazer or midi skirt.",
        "Hey! Welcome. I'm Lenny, and I'm here to help you shop. You can start by typing what you're looking for — try hoodie or trainers.",
        "Hi there! I'm Lenny. Welcome in. I'm here to assist you. Just type to get started — something like green hoodie or beige coat.",
        "Hello! I'm Lenny — welcome to the chat. I'm here to help with whatever you need. You can start by typing; try jacket or boots.",
        "Hey! Lenny here. Welcome. I'm here to help you find something. Type what you're looking for to get started — e.g. navy blazer or pink skirt.",
        "Hi! Welcome. I'm Lenny and I'm here to assist you. Just type what you're after; try a colour and item like vintage dress or loafers.",
        "Hello! I'm Lenny. Welcome in. I'm here to help you shop. You can start by typing — for example, black jacket or green dress.",
        "Hey there! Welcome to the chat. I'm Lenny, and I'm here to help with whatever you need. Type to get started — try silk blouse or heels.",
        "Hi! I'm Lenny — good to have you. I'm here to assist you. You can start by typing what you're looking for; e.g. denim jacket or sneakers.",
        "Hello! Lenny at your service. Welcome. I'm here to help you find whatever you need. Just type — try navy blazer or pink skirt.",
        "Hey! I'm Lenny. Welcome to the chat. I'm here to help with whatever you need. Start by typing; something like winter coat or boots.",
        "Hi there! Welcome. I'm Lenny and I'm here to help you find something. You can type what you're after — try black jacket or green dress.",
        "Hello! I'm Lenny — welcome. I'm here to assist you. Just type what you're looking for to get started. Try floral skirt or sandals.",
        "Hey! Lenny here. Glad you're here. I'm here to help you shop. Type to get started — e.g. green hoodie or beige coat.",
        "Hi! Welcome to the chat. I'm Lenny, and I'm here to help with whatever you need. You can start by typing — dress, jacket, shoes, etc.",
        "Hello! I'm Lenny. Welcome in. I'm here to help you find something. Just type what you're after; try a colour and item like camel coat or jeans.",
        "Hey there! I'm Lenny — welcome. I'm here to assist you. You can start by typing; for example, navy blazer or pink skirt.",
        "Hi! Lenny at your service. Welcome to the chat. I'm here to help with whatever you need. Type to get started — try printed top or trousers.",
        "Hello! Welcome. I'm Lenny and I'm here to help you shop. Just type what you're looking for — e.g. black jacket or green dress.",
        "Hey! I'm Lenny. Good to see you. I'm here to assist you. You can start by typing; something like striped jumper or jeans.",
        "Hi there! I'm Lenny. Welcome. I'm here to help you find whatever you need. Just type — try navy blazer or pink skirt.",
        "Hello! Lenny here. Welcome to the chat. I'm here to help with whatever you need. Start by typing what you're after — leather bag or scarf.",
        "Hey! Welcome in. I'm Lenny, and I'm here to assist you. You can type what you're looking for; try green hoodie or beige coat.",
        "Hi! I'm Lenny — welcome. I'm here to help you find something. Just type to get started — e.g. blazer or ankle boots.",
        "Hello! I'm Lenny. Welcome. I'm here to help with whatever you need. You can start by typing — try black jacket or green dress.",
        "Hey there! Lenny at your service. Welcome to the chat. I'm here to assist you. Type what you're after; for example, coat or trainers.",
        "Hi! Welcome. I'm Lenny and I'm here to help you shop. Just type what you're looking for to get started — navy blazer or pink skirt.",
        "Hello! Lenny here. Good to have you. I'm here to help you find whatever you need. You can start by typing — try midi skirt or heels.",
        "Hey! I'm Lenny — welcome in. I'm here to assist you. Just type; something like dress or shoes works.",
        "Hi there! Welcome to the chat. I'm Lenny, and I'm here to help with whatever you need. Type what you're looking for — e.g. black jacket or green dress.",
        "Hello! I'm Lenny. Welcome. I'm here to help you find something. You can start by typing — try cropped top or wide-leg trousers.",
        "Hey! Lenny at your service. Glad you're here. I'm here to help you shop. Just type to get started — navy blazer or pink skirt.",
        "Hi! I'm Lenny — welcome to the chat. I'm here to assist you with whatever you need. Type what you're after; try bomber jacket or sneakers.",
        "Hello! Welcome. I'm Lenny and I'm here to help. You can start by typing what you're looking for — e.g. green hoodie or beige coat.",
        "Hey there! I'm Lenny. Welcome. I'm here to help you find whatever you need. Just type — try wrap dress or flats.",
        "Hi! Lenny here. Welcome in. I'm here to assist you. You can start by typing; for example, black jacket or green dress.",
        "Hello! I'm Lenny — good to see you. I'm here to help with whatever you need. Type to get started — dress, jacket, shoes, you name it.",
        "Hey! Welcome to the chat. I'm Lenny, and I'm here to help you find something. Just type what you're after — try oversized coat or boots.",
        "Hi there! I'm Lenny. Welcome to the chat. I'm here to assist you. You can start by typing — navy blazer or pink skirt.",
        "Hello! Lenny at your service. Welcome. I'm here to help you shop. Type what you're looking for to get started; try linen shirt or chinos.",
        "Hey! I'm Lenny. Welcome in. I'm here to help with whatever you need. Just type — e.g. black jacket or green dress.",
        "Hi! Welcome. I'm Lenny and I'm here to assist you. You can start by typing what you're after — try puffer jacket or joggers.",
        "Hello! I'm Lenny — welcome to the chat. I'm here to help you find whatever you need. Type to get started; something like slip dress or mules.",
        "Hey there! Lenny here. Welcome. I'm here to assist you. Just type what you're looking for — e.g. navy blazer or pink skirt.",
        "Hi! I'm Lenny. Good to have you. I'm here to help you find something. You can start by typing — try tailored blazer or pumps.",
        "Hello! Welcome to the chat. I'm Lenny, and I'm here to help with whatever you need. Just type; try a colour and item like graphic tee or shorts.",
        "Hey! Lenny at your service. Welcome in. I'm here to help you shop. You can start by typing — for example, black jacket or green dress.",
        "Hi there! I'm Lenny — welcome. I'm here to assist you with whatever you need. Type what you're after to get started — biker jacket or boots.",
        "Hello! I'm Lenny. Welcome to the chat. I'm here to help you find something. Just type to get started — try pleated skirt or loafers.",
        "Hey! Welcome. I'm Lenny and I'm here to help. You can start by typing what you're looking for; e.g. navy blazer or pink skirt.",
        "Hi! Lenny here. Welcome to the chat. I'm here to assist you. Type what you're after — try cashmere sweater or trousers.",
        "Hello! I'm Lenny — welcome in. I'm here to help with whatever you need. Just type; try mini skirt or trainers to get started.",
        "Hey there! Welcome. I'm Lenny, and I'm here to help you find whatever you need. You can start by typing — black jacket or green dress.",
        "Hi! I'm Lenny. Welcome. I'm here to assist you. You can start by typing what you're looking for — try gilet or Chelsea boots.",
        "Hello! Lenny here. Welcome to the chat. I'm here to help you shop. Just type to get started — navy blazer or pink skirt.",
        "Hey! I'm Lenny. Good to see you. I'm here to help with whatever you need. Type what you're after; try satin top or palazzo pants.",
        "Hi there! I'm Lenny — welcome. I'm here to help you find something. You can start by typing — e.g. turtleneck or ankle boots.",
        "Hello! Welcome to the chat. I'm Lenny, and I'm here to assist you. Just type what you're looking for to get started — try blouse or ballet flats.",
        "Hey! Lenny at your service. Welcome in. I'm here to help you find whatever you need. Type to get started; something like parka or trainers.",
        "Hi! Welcome. I'm Lenny and I'm here to help you find something. You can start by typing — try black jacket or green dress.",
        "Hello! I'm Lenny. Welcome to the chat. I'm here to assist you. Just type — e.g. sundress or sandals.",
        "Hey there! Lenny here. Glad you're here. I'm here to help with whatever you need. You can start by typing; try roll neck or smart trousers.",
        "Hi! I'm Lenny — welcome. I'm here to help you shop. Type what you're looking for to get started — navy blazer or pink skirt.",
        "Hello! Welcome. I'm Lenny and I'm here to assist you. Just type what you're after — try waistcoat or brogues.",
        "Hey! I'm Lenny. Welcome. I'm here to help you find whatever you need. You can start by typing — try crop top or high-waist jeans.",
        "Hi there! Welcome to the chat. I'm Lenny, and I'm here to help. Just type to get started; for example, black jacket or green dress.",
        "Hello! Lenny here. Welcome. I'm here to assist you with whatever you need. You can start by typing — red dress or blue shoes.",
        "Hey! I'm Lenny — good to have you. I'm here to help you find something. Type what you're looking for; try checked shirt or desert boots.",
        "Hi! Welcome to the chat. I'm Lenny, and I'm here to help you shop. Just type what you're after to get started — try vest or espadrilles."
    ]

    /// When the query is in scope but we don't have a product type yet (e.g. only colours). Ask for category so we don't run search too early.
    static func replyWhenNeedMoreDetail() -> String {
        needMoreDetailReplies.randomElement() ?? needMoreDetailReplies[0]
    }

    private static let needMoreDetailReplies: [String] = [
        "What type of item are you looking for? For example, dress, jacket, shoes, or bag.",
        "I'd love to help — what kind of product do you have in mind? Dress, coat, trainers, etc.",
        "Got it. What are you after — dress, jacket, shoes, or something else?"
    ]

    /// Out-of-scope replies when the query isn't about products. Varied so the bot doesn't feel robotic.
    static let outOfScopeReplies: [String] = [
        "I don't understand that. I can help you find items by colour, category, or style—try something like \"red dress\" or \"blue shoes\".",
        "I'm not sure about that. I'm best at finding clothes and accessories—try something like pink skirt or navy blazer.",
        "That's outside what I can help with. I can search for items by colour and type—e.g. green hoodie or beige coat."
    ]

    /// Returns a random greeting reply (for use with L10n).
    func randomGreetingReply() -> String {
        Self.greetingReplies.randomElement() ?? Self.greetingReplies[0]
    }

    /// Returns a random out-of-scope reply (for use with L10n).
    static func randomOutOfScopeReply() -> String {
        Self.outOfScopeReplies.randomElement() ?? Self.outOfScopeReplies[0]
    }

    /// True if the term is a valid product category for fallback (avoids "here are some hellos" for greetings).
    func isFallbackTermValid(_ term: String) -> Bool {
        let lower = term.lowercased()
        if Self.nonProductWords.contains(lower) { return false }
        return Self.categoryKeywords.contains(where: { $0.lowercased() == lower })
    }

    /// Reply when we fell back to a broader search (e.g. "dress" when "blue dress" had no results). Feels trained and helpful.
    func replyForFallbackResults(fallbackTerm: String) -> String {
        let warm = Self.warmLeadInPhrases.randomElement() ?? Self.warmLeadInPhrases[0]
        let plural = fallbackTerm.hasSuffix("s") ? fallbackTerm : fallbackTerm + "s"
        return "\(warm) I couldn't find that exact match right now, but here are some \(plural) you might like."
    }

    /// Reply when user asked for a size (e.g. size 10) but we're showing all results because none matched that size.
    func replyForSizeFallback(sizeTerm: String) -> String {
        let warm = Self.warmLeadInPhrases.randomElement() ?? Self.warmLeadInPhrases[0]
        let msg = String(format: L10n.string("We don't have size %@ in these results, but here are some options you might like."), sizeTerm)
        return "\(warm) \(msg)"
    }

    func replyForResults(parsed: ParsedSearch, hasItems: Bool, query: String? = nil) -> String {
        if !hasItems {
            return replyForNoResults()
        }
        let baseReply: String
        if let hint = parsed.closestMatchHint {
            baseReply = hint
        } else if let batch = selectResponseSet(parsed: parsed, query: query), let pick = batch.randomElement() {
            baseReply = pick
        } else {
            let options: [String]
            switch parsed.detectedEvent {
            case .happy:
                options = [
                    L10n.string("Happy to help! Here are some options you might like."),
                    L10n.string("Sounds exciting! Here are some picks for you."),
                    L10n.string("Let's find something great. Here are some options."),
                    L10n.string("Here are some items that could work perfectly."),
                    L10n.string("Hope you find something you love. Here are some options.")
                ]
            case .sad:
                options = [
                    L10n.string("I understand. Here are some appropriate options."),
                    L10n.string("I'll help you find something suitable."),
                    L10n.string("Here are some options that might work."),
                    L10n.string("Let me show you some suitable options.")
                ]
            case .none:
                options = [
                    L10n.string("Here are some items that might work."),
                    L10n.string("Here are some options for you."),
                    L10n.string("These might match what you're looking for."),
                    L10n.string("Here are some picks based on your search.")
                ]
            }
            baseReply = options.randomElement() ?? options[0]
        }
        let warmLeadIn = Self.warmLeadInPhrases.randomElement() ?? Self.warmLeadInPhrases[0]
        var reply = "\(warmLeadIn) \(baseReply)"
        if let (_, corrected) = parsed.spellingCorrectionHint {
            let template = L10n.string("Do you mean \"%@\"?")
            let spellingPrefix = String(format: template, corrected)
            reply = "\(warmLeadIn) \(spellingPrefix) \(baseReply)"
        }
        return reply
    }
    
    /// Fuzzy match a single word against app colours and aliases.
    private func fuzzyMatchColour(word: String) -> String? {
        var best: (colour: String, distance: Int)?
        
        for appColour in Self.appColours {
            let d = Self.levenshtein(word, appColour.lowercased())
            if d <= maxTypoDistance, best == nil || d < best!.distance {
                best = (appColour, d)
            }
        }
        for (alias, appColour) in Self.colourAliases {
            let d = Self.levenshtein(word, alias)
            if d <= maxTypoDistance, best == nil || d < best!.distance {
                best = (appColour, d)
            }
        }
        return best?.colour
    }
    
    /// Levenshtein distance between two strings.
    private static func levenshtein(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
            }
        }
        return d[a.count][b.count]
    }
    
    /// Map a colour name (from our app list) to a simple RGB for distance comparison (e.g. for image colour).
    static func rgb(forColourName name: String) -> (r: Double, g: Double, b: Double)? {
        switch name.lowercased() {
        case "black": return (0, 0, 0)
        case "white": return (1, 1, 1)
        case "red": return (1, 0, 0)
        case "blue": return (0, 0, 1)
        case "green": return (0, 0.5, 0)
        case "yellow": return (1, 1, 0)
        case "pink": return (1, 0.75, 0.8)
        case "purple": return (0.5, 0, 0.5)
        case "orange": return (1, 0.5, 0)
        case "brown": return (0.6, 0.4, 0.2)
        case "grey", "gray": return (0.5, 0.5, 0.5)
        case "beige": return (0.96, 0.96, 0.86)
        case "navy": return (0, 0, 0.5)
        case "maroon": return (0.5, 0, 0)
        case "teal": return (0, 0.5, 0.5)
        default: return nil
        }
    }
    
    /// Find the closest app colour name for a given RGB (0–1). Used for image colour detection.
    static func nearestColourName(r: Double, g: Double, b: Double) -> String {
        var best: (name: String, dist: Double) = (Self.appColours[0], .infinity)
        for name in appColours {
            guard let rgb = rgb(forColourName: name) else { continue }
            let dr = r - rgb.r, dg = g - rgb.g, db = b - rgb.b
            let d = dr*dr + dg*dg + db*db
            if d < best.dist { best = (name, d) }
        }
        return best.name
    }
}
