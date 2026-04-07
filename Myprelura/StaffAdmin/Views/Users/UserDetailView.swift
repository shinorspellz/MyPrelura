import SwiftUI

/// People tab: full consumer `UserProfileView` (shop, filters) using the staff token mirrored into `AuthService`.
struct UserDetailView: View {
    let username: String
    var summary: UserAdminRow? = nil
    @EnvironmentObject private var authService: AuthService
    @Environment(AdminSession.self) private var session

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var publicProfileURL: URL? {
        guard !trimmedUsername.isEmpty else { return nil }
        return Constants.publicProfileURL(username: trimmedUsername)
    }

    private var seedSeller: User {
        User.fromStaffDirectory(username: username, row: summary)
    }

    var body: some View {
        UserProfileView(seller: seedSeller, authService: authService)
            .environment(\.staffAdminSession, session)
            .toolbar {
                if let url = publicProfileURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
    }
}
