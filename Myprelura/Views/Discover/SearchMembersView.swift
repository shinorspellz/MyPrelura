import SwiftUI

/// Search results for "Search members" on Discover. Shows members matching the query with a follow button on each row.
struct SearchMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authService: AuthService
    let query: String

    @State private var members: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    /// Toggling follow per user id (optimistic state); nil = use backend value.
    @State private var followOverride: [UUID: Bool] = [:]
    @State private var togglingUserId: Int?
    private let userService = UserService()

    private func isFollowing(_ user: User) -> Bool {
        if let over = followOverride[user.id] { return over }
        return user.isFollowing ?? false
    }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    emptyQueryView
                } else if isLoading && members.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if members.isEmpty {
                    emptyResultsView
                } else {
                    memberListView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .navigationTitle(L10n.string("Search members"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Done")) { dismiss() }
                        .foregroundColor(Theme.primaryColor)
                }
            }
            .onAppear {
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    loadMembers()
                }
            }
            .onChange(of: query) { _, new in
                if !new.trimmingCharacters(in: .whitespaces).isEmpty {
                    loadMembers()
                } else {
                    members = []
                    errorMessage = nil
                }
            }
            .onChange(of: authService.authToken) { _, _ in
                userService.updateAuthToken(authService.authToken)
            }
        }
    }

    private var emptyQueryView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(L10n.string("Search members"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
            Text("Enter a name or username to find members.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(message)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyResultsView: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(String(format: L10n.string("Results for \"%@\""), query))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.primaryText)
            Text(L10n.string("No members found"))
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var memberListView: some View {
        List(members, id: \.id) { user in
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                NavigationLink(destination: UserProfileView(seller: user, authService: authService)) {
                    HStack(spacing: Theme.Spacing.md) {
                        avatarView(for: user)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.username)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .listRowBackground(Theme.Colors.background)
                .listRowInsets(EdgeInsets(top: 10, leading: Theme.Spacing.md, bottom: 10, trailing: Theme.Spacing.sm))
                .listRowSeparator(.hidden)
                .navigationLinkIndicatorVisibility(.hidden)

                if authService.username != user.username, let userId = user.userId {
                    followButton(user: user, userId: userId)
                        .layoutPriority(1)
                }
            }
            .overlay(ContentDivider(), alignment: .bottom)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func avatarView(for user: User) -> some View {
        Group {
            if let urlString = user.avatarURL, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                    default: Circle().fill(Theme.primaryColor.opacity(0.3))
                        .overlay(Text(String(user.username.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.primaryColor.opacity(0.3))
                    .frame(width: 44, height: 44)
                    .overlay(Text(String(user.username.prefix(1)).uppercased()).font(.system(size: 18, weight: .semibold)).foregroundColor(.white))
            }
        }
    }

    private func followButton(user: User, userId: Int) -> some View {
        let following = isFollowing(user)
        let isToggling = togglingUserId == userId
        return Button {
            Task { await toggleFollow(user: user, userId: userId) }
        } label: {
            if isToggling {
                ProgressView()
                    .scaleEffect(0.9)
                    .frame(minWidth: 84, minHeight: 34)
            } else {
                Text(following ? L10n.string("Following") : L10n.string("Follow"))
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(following ? Theme.Colors.secondaryText : .white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(minWidth: 84, minHeight: 34)
                    .background(
                        Capsule()
                            .fill(following ? Theme.Colors.secondaryBackground : Theme.primaryColor)
                    )
            }
        }
        .disabled(isToggling)
        .buttonStyle(PlainTappableButtonStyle())
        .fixedSize(horizontal: true, vertical: true)
    }

    private func loadMembers() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        followOverride = [:]
        userService.updateAuthToken(authService.authToken)
        Task {
            do {
                let list = try await userService.searchUsers(search: q)
                await MainActor.run {
                    members = list
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = L10n.userFacingError(error)
                    members = []
                    isLoading = false
                }
            }
        }
    }

    private func toggleFollow(user: User, userId: Int) async {
        let currentlyFollowing = isFollowing(user)
        togglingUserId = userId
        followOverride[user.id] = !currentlyFollowing
        defer {
            Task { @MainActor in
                togglingUserId = nil
            }
        }
        do {
            if currentlyFollowing {
                try await userService.unfollowUser(followedId: userId)
            } else {
                try await userService.followUser(followedId: userId)
            }
        } catch {
            await MainActor.run {
                followOverride[user.id] = currentlyFollowing
            }
        }
    }
}
