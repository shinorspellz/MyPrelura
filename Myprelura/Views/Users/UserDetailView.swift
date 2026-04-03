import SwiftUI

struct UserDetailView: View {
    @Environment(AdminSession.self) private var session
    /// Username from navigation (required).
    let username: String
    /// Optional row from `userAdminStats` for seller metrics and avatar fallback.
    var summary: UserAdminRow? = nil

    @State private var profile: UserProfileDTO?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showDeleteConfirm = false
    @State private var actionMessage: String?

    private var displayUsername: String {
        profile?.username ?? username
    }

    private var avatarURL: String? {
        if let p = profile?.profilePictureUrl, !p.isEmpty { return p }
        if let p = profile?.thumbnailUrl, !p.isEmpty { return p }
        if let s = summary?.profilePictureUrl, !s.isEmpty { return s }
        if let s = summary?.thumbnailUrl, !s.isEmpty { return s }
        return nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Theme.Colors.error)
                }
                if let p = profile {
                    GlassCard {
                        HStack(alignment: .top, spacing: Theme.Spacing.md) {
                            Group {
                                if let profileUrl = Constants.publicProfileURL(username: displayUsername) {
                                    NavigationLink {
                                        ConsumerWebPageView(url: profileUrl, title: "@\(displayUsername)")
                                    } label: {
                                        AdminAvatar(urlString: avatarURL, size: 88)
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    AdminAvatar(urlString: avatarURL, size: 88)
                                }
                            }
                            .accessibilityLabel("View live public profile on prelura.uk")

                            VStack(alignment: .leading, spacing: 6) {
                                Text(p.displayName ?? p.username ?? username)
                                    .font(Theme.Typography.title2)
                                Text("@\(displayUsername)")
                                    .font(Theme.Typography.subheadline)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                if let email = p.email, !email.isEmpty {
                                    Text(email)
                                        .font(Theme.Typography.footnote)
                                        .foregroundStyle(Theme.Colors.tertiaryText)
                                }
                                HStack {
                                    Label(p.isVerified == true ? "Verified" : "Not verified", systemImage: p.isVerified == true ? "checkmark.seal.fill" : "xmark.seal")
                                    Spacer()
                                    Label("\(p.listing ?? 0) active listings", systemImage: "bag")
                                }
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            }
                        }
                        Text("Tap the photo for the same public profile experience as the shopper app (prelura.uk).")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Account")
                                .font(Theme.Typography.headline)
                            detailRow("Joined", value: formatDate(p.dateJoined ?? summary?.dateJoined))
                            detailRow("Last login", value: formatDate(p.lastLogin ?? summary?.lastLogin))
                            detailRow("Last seen", value: formatDate(p.lastSeen ?? summary?.lastSeen))
                            detailRow("Followers", value: "\(p.noOfFollowers ?? summary?.noOfFollowers ?? 0)")
                            detailRow("Following", value: "\(p.noOfFollowing ?? summary?.noOfFollowing ?? 0)")
                            if let credit = p.credit ?? summary?.credit {
                                detailRow("Credit", value: "\(credit)")
                            }
                            if let fn = p.firstName ?? summary?.firstName, let ln = p.lastName ?? summary?.lastName, !fn.isEmpty || !ln.isEmpty {
                                detailRow("Legal name", value: "\(fn) \(ln)".trimmingCharacters(in: .whitespaces))
                            }
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Commerce (seller-facing)")
                                .font(Theme.Typography.headline)
                            if let s = summary {
                                detailRow("Active listings", value: "\(s.activeListings ?? 0)")
                                detailRow("Total listings", value: "\(s.totalListings ?? 0)")
                                detailRow("Delivered sales total", value: s.totalSales?.display ?? "—")
                                detailRow("Shop inventory value", value: s.totalShopValue?.display ?? "—")
                            } else {
                                Text("Open this user from People to attach seller stats from `userAdminStats`.")
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                            }
                            detailRow("Purchases as buyer", value: "Not exposed on GraphQL yet")
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Trust score (internal)")
                                .font(Theme.Typography.headline)
                            Text("\(trustScore(for: p)) / 100")
                                .font(Theme.Typography.largeTitle)
                                .foregroundStyle(Theme.primaryColor)
                            Text("Derived from verification, reviews, and listing count. Flag users who deviate from healthy patterns.")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                            if (p.reviewStats?.noOfReviews ?? 0) > 0 {
                                Text("Reviews: \(p.reviewStats?.noOfReviews ?? 0) · Avg \(String(format: "%.1f", p.reviewStats?.rating ?? 0))")
                                    .font(Theme.Typography.subheadline)
                            }
                        }
                    }

                    if let bio = p.bio, !bio.isEmpty {
                        GlassCard {
                            Text(bio)
                                .font(Theme.Typography.body)
                                .foregroundStyle(Theme.Colors.primaryText)
                        }
                    }

                    if session.accessLevel.canDeleteUsers {
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Admin actions")
                                    .font(Theme.Typography.headline)
                                Text("Flag user removes the account via the existing dashboard mutation (same as Django moderation flow).")
                                    .font(Theme.Typography.footnote)
                                    .foregroundStyle(Theme.Colors.secondaryText)
                                Button(role: .destructive) {
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Flag & remove user…", systemImage: "person.crop.circle.badge.xmark")
                                }
                            }
                        }
                    } else {
                        GlassCard {
                            Text("Staff can inspect profiles. Only admins can run destructive account actions in this build.")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.Colors.secondaryText)
                        }
                    }

                    if let actionMessage {
                        Text(actionMessage)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.primaryText)
                    }
                } else if !isLoading {
                    ContentUnavailableView(
                        "Profile unavailable",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("This account may be private, removed, or the username may not match the API. Try opening the public profile from the People list again.")
                    )
                    .padding(.top, Theme.Spacing.lg)
                }
            }
            .padding()
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .task { await load() }
        .confirmationDialog("Flag this user? This uses the backend flagUser mutation.", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Confirm flag (TERMS_VIOLATION)", role: .destructive) {
                Task { await flagUser() }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func detailRow(_ title: String, value: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.secondaryText)
            Spacer()
            Text(value?.isEmpty == false ? value! : "—")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.primaryText)
                .multilineTextAlignment(.trailing)
        }
    }

    private func formatDate(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: raw) {
            return d.formatted(date: .abbreviated, time: .shortened)
        }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: raw) {
            return d.formatted(date: .abbreviated, time: .shortened)
        }
        return raw
    }

    private func trustScore(for p: UserProfileDTO) -> Int {
        var s = 50
        if p.isVerified == true { s += 20 }
        let reviews = p.reviewStats?.noOfReviews ?? 0
        let rating = p.reviewStats?.rating ?? 0
        if reviews > 0 {
            s += min(20, Int((rating / 5.0) * 20))
        }
        s += min(10, (p.listing ?? 0) * 2)
        return min(100, s)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            profile = try await PreluraAdminAPI.getUser(client: session.graphQL, username: username)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func flagUser() async {
        guard let id = profile?.id else { return }
        do {
            let r = try await PreluraAdminAPI.flagUser(
                client: session.graphQL,
                userId: String(id),
                reason: "TERMS_VIOLATION",
                notes: "Myprelura admin action"
            )
            actionMessage = r.message ?? (r.success == true ? "OK" : "Failed")
        } catch {
            actionMessage = error.localizedDescription
        }
    }
}
