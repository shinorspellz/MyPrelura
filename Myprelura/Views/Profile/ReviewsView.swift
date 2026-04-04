import SwiftUI

/// Reviews list for a user (matches Flutter ReviewScreen / review_tab.dart).
struct ReviewsView: View {
    let username: String
    let rating: Double
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    private let userService = UserService()

    @State private var reviews: [UserReview] = []
    @State private var totalNumber: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFilter: ReviewFilter = .all

    enum ReviewFilter: String, CaseIterable {
        case all = "All"
        case fromMembers = "From members"
        case automatic = "Automatic"
    }

    var body: some View {
        Group {
            if isLoading && reviews.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        headerSection
                        howReviewsWorkSection
                        ContentDivider()
                        filterSection
                        if reviews.isEmpty {
                            Text(L10n.string("No reviews yet"))
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Theme.Spacing.xl)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(reviews) { review in
                                    reviewCard(review)
                                    ContentDivider()
                                        .padding(.leading, Theme.Spacing.md + 35 + 16)
                                }
                            }
                        }
                    }
                }
                .refreshable {
                    await loadReviews()
                }
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Reviews"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let token = authService.authToken {
                userService.updateAuthToken(token)
            }
            Task { await loadReviews() }
        }
        .onChange(of: authService.authToken) { _, new in
            userService.updateAuthToken(new)
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(String(format: "%.1f", rating))
                .font(Theme.Typography.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(Theme.Colors.primaryText)
            HStack(spacing: Theme.Spacing.xs) {
                StarRatingView(rating: rating, size: 15)
                Text("(\(totalNumber))")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(L10n.string("Member reviews (%@)").replacingOccurrences(of: "%@", with: "\(totalNumber)"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text("\(String(format: "%.1f", rating))")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    StarRatingView(rating: 1, size: 12)
                }
                HStack {
                    Text(L10n.string("Automatic reviews (0)"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text("5.0")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    StarRatingView(rating: 1, size: 12)
                }
            }
            .padding(.top, Theme.Spacing.sm)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var howReviewsWorkSection: some View {
        Button(action: {}) {
            Text(L10n.string("How reviews work"))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.primaryColor)
        }
        .buttonStyle(HapticTapButtonStyle())
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var filterSection: some View {
        HStack(spacing: Theme.Spacing.sm) {
            ForEach(ReviewFilter.allCases, id: \.self) { filter in
                PillTag(
                    title: filter.rawValue,
                    isSelected: selectedFilter == filter,
                    accentWhenUnselected: true,
                    action: { selectedFilter = filter }
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func reviewCard(_ review: UserReview) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            avatarView(review)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(review.reviewerUsername.isEmpty ? "User" : review.reviewerUsername)
                        .font(Theme.Typography.headline)
                        .fontWeight(.bold)
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text(timeAgo(from: review.dateCreated))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                StarRatingView(rating: Double(review.rating), size: 14)
                Text(review.comment)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func avatarView(_ review: UserReview) -> some View {
        Group {
            if let urlString = review.reviewerProfilePictureUrl, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Circle()
                            .fill(Theme.primaryColor.opacity(0.3))
                            .overlay(
                                Text(String(review.reviewerUsername.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 35, height: 35)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.primaryColor.opacity(0.3))
                    .frame(width: 35, height: 35)
                    .overlay(
                        Text(String(review.reviewerUsername.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                    )
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "1s" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        if interval < 604800 { return "\(Int(interval / 86400))d" }
        return "\(Int(interval / 604800))w"
    }

    private func loadReviews() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        defer { Task { @MainActor in isLoading = false } }
        do {
            let result = try await userService.getUserReviews(username: username)
            await MainActor.run {
                reviews = result.reviews
                totalNumber = result.totalNumber
            }
        } catch {
            await MainActor.run {
                errorMessage = L10n.userFacingError(error)
                reviews = []
            }
        }
    }
}

// MARK: - Star rating (matches Flutter Ratings widget)
private struct StarRatingView: View {
    let rating: Double
    var size: CGFloat = 15
    private let starColor = Color(red: 1, green: 0.8, blue: 0) // amber/gold

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { i in
                Image(systemName: Double(i) <= rating ? "star.fill" : (Double(i) - 0.5 <= rating ? "star.leadinghalf.filled" : "star"))
                    .font(.system(size: size))
                    .foregroundColor(starColor)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ReviewsView(username: "seller1", rating: 4.8)
            .environmentObject(AuthService())
    }
}
