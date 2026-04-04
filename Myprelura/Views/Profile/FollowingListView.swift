import SwiftUI

/// List of users that the given user follows (Flutter FollowingRoute).
struct FollowingListView: View {
    let username: String
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var users: [User] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let userService = UserService()

    var body: some View {
        Group {
            if isLoading && users.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if users.isEmpty && errorMessage == nil {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.2")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("Not following anyone yet"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(error)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(users, id: \.id) { user in
                    NavigationLink(destination: UserProfileView(seller: user, authService: authService)) {
                        HStack(spacing: Theme.Spacing.md) {
                            avatarView(for: user)
                            Text(user.username)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Theme.Spacing.xs)
                        .contentShape(Rectangle())
                        .overlay(
                            ContentDivider(),
                            alignment: .bottom
                        )
                    }
                    .listRowBackground(Theme.Colors.background)
                    .listRowInsets(EdgeInsets(top: 8, leading: Theme.Spacing.md, bottom: 8, trailing: Theme.Spacing.md))
                    .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .navigationLinkIndicatorVisibility(.hidden)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Following"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            loadFollowing()
        }
        .onChange(of: authService.authToken) { _, newToken in
            userService.updateAuthToken(newToken)
        }
    }

    private func avatarView(for user: User) -> some View {
        Group {
            if let urlString = user.avatarURL, let url = URL(string: urlString) {
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

    private func loadFollowing() {
        isLoading = true
        errorMessage = nil
        userService.updateAuthToken(authService.authToken)
        Task {
            do {
                let list = try await userService.getFollowing(username: username)
                await MainActor.run {
                    users = list
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    users = []
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FollowingListView(username: "test")
            .environmentObject(AuthService())
    }
}
