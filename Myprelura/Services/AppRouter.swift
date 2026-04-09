import Combine
import Foundation
import SwiftUI

/// Destination opened from a deep link or push notification (matches Flutter notification_service routes).
enum DeepLinkDestination: Equatable {
    /// Numeric product id or public `listingCode` (same resolver as web `/item/{slug}`).
    case product(publicSlug: String)
    case user(username: String)
    case conversation(conversationId: String, username: String, isOffer: Bool, isOrder: Bool)
    /// Push: order shipped / generic order tap when no chat thread id is present.
    case orderDetail(orderId: Int)
    /// Push: `ORDER_ISSUE` with buyer–seller order conversation id.
    case orderIssueSupport(conversationId: String, orderId: String?, peerUsername: String)
}

/// Wrapper so we can use fullScreenCover(item:) with optional DeepLinkDestination.
struct DeepLinkDestinationItem: Identifiable {
    let id = UUID()
    let destination: DeepLinkDestination
}

/// Chat / order-thread push: open the existing inbox stack instead of a full-screen overlay (native back = Messages list).
struct PendingInboxChatNavigation: Equatable {
    let conversationId: String
    let username: String
}

/// Handles deep links (URL scheme / universal links) and push notification tap payloads; holds pending destination for the UI to present.
final class AppRouter: ObservableObject {
    @Published var pendingItem: DeepLinkDestinationItem?
    /// When set, `MainTabView` switches to Inbox and pushes this thread on the tab’s `NavigationStack` (same UX as opening from the list).
    @Published var pendingInboxChat: PendingInboxChatNavigation?
    /// Myprelura staff: local notification tap to open Console (`myprelura_open_console` / `page: STAFF_CONSOLE`).
    @Published var pendingStaffConsoleOpen = false

    /// Marketing / public-web hosts that may serve `/item/*` and optional `/{username}` profile paths.
    private static func isPreluraItemUniversalLinkHost(_ host: String) -> Bool {
        switch host.lowercased() {
        case "wearhouse.co.uk", "www.wearhouse.co.uk",
             "mywearhouse.co.uk", "www.mywearhouse.co.uk",
             "prelura.uk", "www.prelura.uk", "prelura.com", "www.prelura.com":
            return true
        default:
            return false
        }
    }

    /// API host where Django serves `apple-app-site-association` plus `/app/u/*` and `/join*`.
    private static let apiUniversalLinkHosts: Set<String> = ["prelura.voltislabs.uk", "www.prelura.voltislabs.uk"]

    private static func isHttpsUniversalLinkHost(_ host: String) -> Bool {
        let h = host.lowercased()
        return isPreluraItemUniversalLinkHost(h) || apiUniversalLinkHosts.contains(h)
    }

    private static let reservedProfilePathSegments: Set<String> = [
        "item", "join", "app", "terms", "privacy", "login", "sell", "cart", "checkout",
        "discover", "api", "graphql", "admin", "static", "assets", "_next", "help",
        "support", "about", "contact", "blog", "legal", "cookies", "sitemap", "robots.txt",
        "download", "invite", "internal", "ws", "media", "register", "signin", "signup",
    ]

    private static func looksLikePublicUsernameSegment(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        guard !reservedProfilePathSegments.contains(lower) else { return false }
        let decoded = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2 ... 40).contains(decoded.count) else { return false }
        return decoded.range(of: "^[a-zA-Z0-9_]+$", options: .regularExpression) != nil
    }

    /// Pops the pending inbox navigation if present (call from main thread / `MainActor`).
    func consumePendingInboxChat() -> PendingInboxChatNavigation? {
        let r = pendingInboxChat
        pendingInboxChat = nil
        return r
    }

    /// Handle URL (e.g. prelura://product/Ab3xY9k2Mn, https://mywearhouse.co.uk/item/Ab3xY9k2Mn, prelura://user/john).
    func handle(url: URL) {
        var dest: DeepLinkDestination?
        let scheme = (url.scheme ?? "").lowercased()

        if scheme == "http" || scheme == "https" {
            let host = (url.host ?? "").lowercased()
            guard Self.isHttpsUniversalLinkHost(host) else { return }
            let isApiHost = Self.apiUniversalLinkHosts.contains(host)
            let parts = url.path.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            if parts.count >= 2, parts[0].lowercased() == "item" {
                let raw = parts[1]
                let slug = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if !slug.isEmpty {
                    dest = .product(publicSlug: slug)
                }
            } else if parts.count >= 3, parts[0].lowercased() == "app", parts[1].lowercased() == "u" {
                let raw = parts[2]
                let username = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
                if Self.looksLikePublicUsernameSegment(raw) {
                    dest = .user(username: username)
                }
            } else if parts.count >= 1, parts[0].lowercased() == "join" {
                dest = nil
            } else if !isApiHost, parts.count == 1, Self.looksLikePublicUsernameSegment(parts[0]) {
                let raw = parts[0]
                let username = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
                dest = .user(username: username)
            }
        } else {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let host = components.host else {
                return
            }
            let pathComponents = components.path.split(separator: "/").map(String.init)
            switch host.lowercased() {
            case "product":
                if let raw = pathComponents.first {
                    let slug = (raw.removingPercentEncoding ?? raw).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !slug.isEmpty {
                        dest = .product(publicSlug: slug)
                    }
                }
            case "user", "profile":
                if let username = pathComponents.first, !username.isEmpty {
                    dest = .user(username: username)
                }
            case "chat", "conversation":
                if let id = pathComponents.first {
                    let username = components.queryItems?.first(where: { $0.name == "username" })?.value ?? ""
                    let isOffer = (components.queryItems?.first(where: { $0.name == "is_offer" })?.value ?? "false").lowercased() == "true"
                    let isOrder = (components.queryItems?.first(where: { $0.name == "is_order" })?.value ?? "false").lowercased() == "true"
                    dest = .conversation(conversationId: String(id), username: username, isOffer: isOffer, isOrder: isOrder)
                }
            case "join", "invite":
                break
            default:
                break
            }
        }

        if let d = dest {
            Task { @MainActor in
                self.pendingItem = DeepLinkDestinationItem(destination: d)
            }
        }
    }

    private static func stringKey(_ any: AnyHashable) -> String {
        (any as? String) ?? String(describing: any)
    }

    /// Read notification payload values (FCM often sends strings; keys may vary in casing).
    static func pushValue(_ p: [AnyHashable: Any], _ key: String) -> Any? {
        if let v = p[AnyHashable(key)] { return v }
        let lower = key.lowercased()
        for (k, v) in p {
            let ks = stringKey(k)
            if ks.lowercased() == lower { return v }
        }
        return nil
    }

    static func pushString(_ p: [AnyHashable: Any], _ key: String) -> String? {
        guard let raw = pushValue(p, key) else { return nil }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty || t.lowercased() == "none" { return nil }
            return t
        }
        if let i = raw as? Int { return String(i) }
        if let n = raw as? NSNumber { return n.stringValue }
        return nil
    }

    /// Parses booleans from FCM (`"True"`, `"1"`) and JSON types.
    static func pushTruthy(_ p: [AnyHashable: Any], _ key: String) -> Bool {
        guard let raw = pushValue(p, key) else { return false }
        if let b = raw as? Bool { return b }
        if let n = raw as? NSNumber { return n.boolValue }
        if let s = raw as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["true", "1", "yes"].contains(t)
        }
        return false
    }

    static func conversationIdFromPayload(_ p: [AnyHashable: Any]) -> String? {
        if let s = pushString(p, "conversation_id"), !s.isEmpty { return s }
        let page = pushString(p, "page")?.uppercased()
        if page == "CONVERSATION", let oid = pushString(p, "object_id"), !oid.isEmpty {
            return oid
        }
        return nil
    }

    /// Flattens FCM/APNs `userInfo` so backend custom keys are readable (top-level, nested `data`, JSON string, `google.c.fcm_data`).
    static func normalizedPushUserInfo(_ userInfo: [AnyHashable: Any]) -> [AnyHashable: Any] {
        var out: [String: Any] = [:]
        for (k, v) in userInfo {
            out[stringKey(k)] = v
        }
        if let nested = userInfo[AnyHashable("data")] as? [String: Any] {
            for (k, v) in nested {
                out[String(describing: k)] = v
            }
        }
        if let dataStr = userInfo[AnyHashable("data")] as? String,
           let d = dataStr.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            for (k, v) in obj {
                out[String(describing: k)] = v
            }
        }
        for (k, v) in userInfo {
            let ks = stringKey(k)
            guard ks.contains("fcm_data") || ks == "google.c.fcm_data" else { continue }
            guard let s = v as? String,
                  let d = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { continue }
            for (kk, vv) in obj {
                out[String(describing: kk)] = vv
            }
        }
        return Dictionary(uniqueKeysWithValues: out.map { (AnyHashable($0.key), $0.value) })
    }

    /// Opens the thread on the Inbox tab’s navigation stack (same as tapping the row in Messages).
    private func enqueueInboxChatOpen(conversationId: String, username: String) {
        Task { @MainActor in
            self.pendingInboxChat = PendingInboxChatNavigation(conversationId: conversationId, username: username)
        }
    }

    /// Handle push notification payload (same keys as Flutter: page, object_id, conversation_id, title, is_offer, is_order).
    /// Also accepts `username` / `sender_username` for chat; `title` may come from aps.alert.
    func handle(notificationPayload: [AnyHashable: Any]) {
        let p = Self.normalizedPushUserInfo(notificationPayload)
        if Self.pushTruthy(p, "myprelura_open_console") {
            Task { @MainActor in self.pendingStaffConsoleOpen = true }
            return
        }
        if Self.pushString(p, "page")?.uppercased() == "STAFF_CONSOLE" {
            Task { @MainActor in self.pendingStaffConsoleOpen = true }
            return
        }
        var page = Self.pushString(p, "page")?.trimmingCharacters(in: .whitespacesAndNewlines)
        if page?.isEmpty != false {
            let hasConv = Self.conversationIdFromPayload(p) != nil
            if hasConv { page = "MESSAGE" }
        }
        guard let pageRaw = page, !pageRaw.isEmpty else { return }
        let pageUpper = pageRaw.uppercased()

        var dest: DeepLinkDestination?

        switch pageUpper {
        case "ORDER_ISSUE":
            if let cid = Self.conversationIdFromPayload(p), Int(cid) != nil {
                dest = .orderIssueSupport(
                    conversationId: cid,
                    orderId: Self.pushString(p, "order_id"),
                    peerUsername: Self.pushString(p, "title")
                        ?? Self.pushString(p, "username")
                        ?? Self.pushString(p, "sender_username")
                        ?? "Order"
                )
            } else if let oid = Self.pushString(p, "order_id").flatMap({ Int($0) }) {
                dest = .orderDetail(orderId: oid)
            }

        case "PRODUCT", "PRODUCT_FLAG", "LISTING":
            if let s = Self.pushString(p, "object_id"), !s.isEmpty {
                dest = .product(publicSlug: s)
            } else if let id = Self.pushValue(p, "object_id") as? Int {
                dest = .product(publicSlug: String(id))
            }

        case "USER", "PROFILE", "FOLLOW":
            if let username = Self.pushString(p, "object_id") {
                dest = .user(username: username)
            }

        case "ORDER":
            if let cid = Self.conversationIdFromPayload(p), !cid.isEmpty {
                let peerName: String = {
                    if let t = Self.pushString(p, "title"), !t.isEmpty { return t }
                    if let u = Self.pushString(p, "username"), !u.isEmpty { return u }
                    if let s = Self.pushString(p, "sender_username"), !s.isEmpty { return s }
                    return "Chat"
                }()
                enqueueInboxChatOpen(conversationId: cid, username: peerName)
            } else if let oid = Self.pushString(p, "order_id").flatMap({ Int($0) })
                ?? Self.pushString(p, "object_id").flatMap({ Int($0) }) {
                dest = .orderDetail(orderId: oid)
            }

        case "CONVERSATION", "OFFER", "MESSAGE", "CHAT":
            guard let convId = Self.conversationIdFromPayload(p), !convId.isEmpty else { break }
            let peerName: String = {
                if let t = Self.pushString(p, "title"), !t.isEmpty { return t }
                if let u = Self.pushString(p, "username"), !u.isEmpty { return u }
                if let s = Self.pushString(p, "sender_username"), !s.isEmpty { return s }
                if let aps = p[AnyHashable("aps")] as? [String: Any],
                   let alert = aps["alert"] as? [String: Any],
                   let t = alert["title"] as? String, !t.isEmpty {
                    return t
                }
                return "Chat"
            }()
            enqueueInboxChatOpen(conversationId: convId, username: peerName)

        default:
            break
        }

        if let d = dest {
            Task { @MainActor in
                self.pendingItem = DeepLinkDestinationItem(destination: d)
            }
        }
    }

    func clearPending() {
        Task { @MainActor in
            self.pendingItem = nil
        }
    }

    func clearPendingStaffConsole() {
        Task { @MainActor in
            self.pendingStaffConsoleOpen = false
        }
    }
}
