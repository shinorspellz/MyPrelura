import Foundation

/// Category selected in the sell flow (backend id + name + full path for tracing back).
struct SellCategory: Equatable {
    let id: String
    let name: String
    /// Full path from root to this category (e.g. ["Men", "Accessories", "Gloves"]) so user can trace back.
    let pathNames: [String]
    /// Full path of IDs for each level.
    let pathIds: [String]
    /// Server-provided full path (e.g. "Men > Clothing > T-Shirts"). Used for sizes(path) to match Flutter; falls back to pathNames if nil.
    let fullPath: String?

    init(id: String, name: String, pathNames: [String]? = nil, pathIds: [String]? = nil, fullPath: String? = nil) {
        self.id = id
        self.name = name
        self.pathNames = pathNames ?? [name]
        self.pathIds = pathIds ?? [id]
        self.fullPath = fullPath
    }

    /// Path for sizes(path) API: use server fullPath when available (matches Flutter), else first two path segments. Normalizes Boys/Girls → Kids like backend.
    var sizeApiPath: String {
        let raw: String
        if let fp = fullPath, !fp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parts = fp.split(separator: ">").map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2 {
                raw = "\(parts[0]) > \(parts[1])"
            } else {
                raw = pathNames.prefix(2).joined(separator: " > ")
            }
        } else {
            raw = pathNames.prefix(2).joined(separator: " > ")
        }
        let lower = raw.lowercased()
        if lower.hasPrefix("boys") {
            return "Kids" + raw.dropFirst(4)
        }
        if lower.hasPrefix("girls") {
            return "Kids" + raw.dropFirst(5)
        }
        return raw
    }

    /// Display string for the sell form (e.g. "Men > Accessories > Gloves").
    var displayPath: String {
        pathNames.joined(separator: " > ")
    }
}

/// A category with its full path (for search results).
struct CategoryPathEntry: Equatable {
    let id: String
    let name: String
    let pathNames: [String]
    let pathIds: [String]
    var displayPath: String { pathNames.joined(separator: " > ") }
}

/// Category node from GraphQL categories(parentId) query (matches Flutter Categoriess / CategoryTypes).
struct APICategory: Decodable {
    let id: String
    let name: String
    let hasChildren: Bool?
    let fullPath: String?

    enum CodingKeys: String, CodingKey {
        case id, name, fullPath, hasChildren
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = ""
        }
        name = try c.decode(String.self, forKey: .name)
        hasChildren = try c.decodeIfPresent(Bool.self, forKey: .hasChildren)
        fullPath = try c.decodeIfPresent(String.self, forKey: .fullPath)
    }
}

/// Material from GraphQL materials() query (backend returns BrandType: id, name).
struct APIMaterial: Decodable {
    let id: Int
    let name: String
}
