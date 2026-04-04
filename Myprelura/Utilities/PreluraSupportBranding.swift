import SwiftUI

/// UI for the system Prelura support user (`prelura_support` on the backend).
enum PreluraSupportBranding {
    /// Backend default from `SUPPORT_SYSTEM_USERNAME`.
    static let systemUsernameLowercased = "prelura_support"

    static func isSupportRecipient(username: String) -> Bool {
        let n = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if n == systemUsernameLowercased { return true }
        if n == "prelura support" { return true }
        if n.replacingOccurrences(of: " ", with: "_") == systemUsernameLowercased { return true }
        if n.replacingOccurrences(of: "_", with: "") == "prelurasupport" { return true }
        return false
    }

    /// Same account when they appear as message/notification **sender**.
    static func isSupportSender(username: String?) -> Bool {
        guard let username, !username.isEmpty else { return false }
        return isSupportRecipient(username: username)
    }

    /// Navigation bar + inbox title (human-readable).
    static func displayTitle(forRecipientUsername username: String) -> String {
        if isSupportRecipient(username: username) {
            return "Prelura Support"
        }
        return username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    static func supportAvatar(size: CGFloat) -> some View {
        Image("PreluraSupportAvatar")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
    }
}
