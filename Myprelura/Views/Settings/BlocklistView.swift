import SwiftUI

/// Blocklist: list blocked users and unblock. Matches Flutter BlockedUsersSettingsScreen.
struct BlocklistView: View {
    @State private var users: [BlockedUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var unblockUserId: Int?
    @State private var unblockUsername: String = ""
    @State private var showUnblockAlert = false

    private let userService = UserService()
    private let pageCount = 20

    var body: some View {
        VStack(spacing: 0) {
            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
            }
            if isLoading && users.isEmpty {
                ProgressView()
                    .padding(Theme.Spacing.xl)
                Spacer()
            } else if users.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "person.slash")
                        .font(.system(size: 44))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("No blocked users"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(users) { user in
                        HStack(spacing: Theme.Spacing.md) {
                            if let urlString = user.profilePictureUrl ?? user.thumbnailUrl,
                               let url = URL(string: urlString) {
                                AsyncImage(url: url) { image in
                                    image.resizable().scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Theme.Colors.secondaryBackground)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Text(String((user.username.prefix(1))).uppercased())
                                            .font(Theme.Typography.body)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    )
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(user.username)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(Theme.Colors.primaryText)
                                Text("@\(user.username)")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            Spacer()
                            Button("Unblock") {
                                unblockUserId = user.id
                                unblockUsername = user.username
                                showUnblockAlert = true
                            }
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.primaryColor)
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Blocklist"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task { await load() }
        .refreshable { await load() }
        .alert("Unblock user?", isPresented: $showUnblockAlert) {
            Button("Cancel", role: .cancel) {
                unblockUserId = nil
                unblockUsername = ""
            }
            Button("Unblock") {
                if let id = unblockUserId {
                    Task { await unblock(userId: id) }
                }
                unblockUserId = nil
                unblockUsername = ""
            }
        } message: {
            if !unblockUsername.isEmpty {
                Text(String(format: L10n.string("Do you want to unblock %@?"), unblockUsername))
            }
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            users = try await userService.getBlockedUsers(pageNumber: 1, pageCount: pageCount, search: searchText.isEmpty ? nil : searchText)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func unblock(userId: Int) async {
        do {
            try await userService.unblockUser(userId: userId)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
