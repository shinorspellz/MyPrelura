import Foundation

/// Picks smaller product images for inbox rows and chat headers (prefers `thumbnail` in JSON image blobs from upload pipeline).
enum ProductListImageURL {
    /// First entry in `imagesUrl` from GraphQL — often a JSON string `{"url":"...","thumbnail":"..."}`.
    static func preferredString(fromImagesUrlArray imagesUrl: [String]?) -> String? {
        guard let first = imagesUrl?.first?.trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else { return nil }
        return preferredString(from: first)
    }

    /// GraphQL may return a flat `[String: String]` image object instead of a JSON string.
    static func preferredString(fromStringKeyedJSON dict: [String: String]) -> String? {
        var obj: [String: Any] = [:]
        for (k, v) in dict { obj[k] = v }
        return resolvedString(fromJSON: obj)
    }

    /// Raw cell from API: JSON object string or plain `https://` URL.
    static func preferredString(from raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("{"),
           let data = raw.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return resolvedString(fromJSON: obj)
        }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") { return raw }
        return nil
    }

    static func url(forListDisplay raw: String?) -> URL? {
        guard let s = preferredString(from: raw) else { return nil }
        return URL(string: s)
    }

    private static func resolvedString(fromJSON json: [String: Any]) -> String? {
        let main = firstNonEmptyString(in: json, keys: ["url", "image_url", "image", "src", "imageUrl"])
        let thumb = firstNonEmptyString(in: json, keys: ["thumbnail", "thumb", "thumbnailUrl", "thumbnail_url"])
        guard let mainTrimmed = main, !mainTrimmed.isEmpty else {
            guard let t = thumb, !t.isEmpty else { return nil }
            if t.hasPrefix("http://") || t.hasPrefix("https://") { return t }
            return nil
        }
        guard let thumbTrimmed = thumb, !thumbTrimmed.isEmpty else { return mainTrimmed }
        if thumbTrimmed.hasPrefix("http://") || thumbTrimmed.hasPrefix("https://") { return thumbTrimmed }
        return resolveRelativeThumbnail(fullURLString: mainTrimmed, thumbnailRef: thumbTrimmed) ?? mainTrimmed
    }

    private static func firstNonEmptyString(in json: [String: Any], keys: [String]) -> String? {
        for k in keys {
            guard let s = json[k] as? String else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return nil
    }

    /// When `thumbnail` is an S3 key or same-directory filename, join with the full image URL’s directory.
    static func resolveRelativeThumbnail(fullURLString: String, thumbnailRef: String) -> String? {
        guard let base = URL(string: fullURLString) else { return nil }
        let ref = thumbnailRef.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ref.isEmpty else { return nil }
        if ref.hasPrefix("http://") || ref.hasPrefix("https://") { return ref }
        let thumbFile = (ref as NSString).lastPathComponent
        guard !thumbFile.isEmpty else { return nil }
        let dir = base.deletingLastPathComponent()
        return dir.appendingPathComponent(thumbFile).absoluteString
    }
}
