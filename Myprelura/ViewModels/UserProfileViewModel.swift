import Foundation
import Combine

@MainActor
class UserProfileViewModel: ObservableObject {
    @Published var user: User
    @Published var items: [Item] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// Follow state for other user's profile (synced from user.isFollowing on load, updated on toggle).
    @Published var isFollowing: Bool = false
    /// Followers count shown in header (synced from user, updated optimistically on follow/unfollow).
    @Published var displayedFollowersCount: Int = 0
    @Published var isTogglingFollow: Bool = false

    private let userService: UserService
    private let productService: ProductService

    var topBrands: [String] {
        let brandCounts = Dictionary(grouping: items.compactMap { $0.brand }, by: { $0 })
            .mapValues { $0.count }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key.localizedCompare(b.key) == .orderedAscending
            }
        return Array(brandCounts.prefix(10).map { $0.key })
    }

    var categoriesWithCounts: [(name: String, count: Int)] {
        let categoryCounts = Dictionary(grouping: items, by: { $0.categoryName ?? $0.category.name })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
        return categoryCounts
    }

    init(seller: User, authService: AuthService?) {
        self.user = seller
        let client = GraphQLClient()
        if let token = authService?.authToken {
            client.setAuthToken(token)
        } else if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            client.setAuthToken(token)
        }
        self.userService = UserService(client: client)
        self.productService = ProductService(client: client)
    }

    func load() {
        Task {
            await loadProfileAndProducts()
        }
    }
    
    private func loadProfileAndProducts() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            // Fetch full profile (bio, location, stats) for this username
            let profileUser = try await userService.getUserByUsername(user.username)
            await MainActor.run {
                self.user = profileUser
                self.isFollowing = profileUser.isFollowing ?? false
                self.displayedFollowersCount = profileUser.followersCount
            }
            let products = try await userService.getUserProducts(username: user.username)
            await MainActor.run {
                self.items = products
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func loadProducts() async {
        await MainActor.run { isLoading = true; errorMessage = nil; items = [] }
        do {
            let products = try await userService.getUserProducts(username: user.username)
            await MainActor.run {
                self.items = products
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func refresh() {
        Task { await loadProfileAndProducts() }
    }

    func refreshAsync() async {
        await loadProfileAndProducts()
    }

    /// Toggle follow state; call from Follow switch. Uses user.userId as followedId. Optimistic update.
    func toggleFollow(authToken: String?) async {
        guard let followedId = user.userId else { return }
        let wasFollowing = isFollowing
        isFollowing.toggle()
        displayedFollowersCount += isFollowing ? 1 : -1
        if displayedFollowersCount < 0 { displayedFollowersCount = 0 }
        isTogglingFollow = true
        defer { isTogglingFollow = false }
        userService.updateAuthToken(authToken)
        do {
            if wasFollowing {
                try await userService.unfollowUser(followedId: followedId)
            } else {
                try await userService.followUser(followedId: followedId)
            }
        } catch {
            isFollowing = wasFollowing
            displayedFollowersCount += wasFollowing ? 1 : -1
            if displayedFollowersCount < 0 { displayedFollowersCount = 0 }
            errorMessage = error.localizedDescription
        }
    }

    /// Toggle like on a listing (same optimistic pattern as `ProfileViewModel`).
    func toggleLike(productId: String) {
        guard !productId.isEmpty, let item = items.first(where: { $0.productId == productId }) else { return }
        let newLiked = !item.isLiked
        let newCount = item.likeCount + (newLiked ? 1 : -1)
        let optimistic = item.with(likeCount: max(0, newCount), isLiked: newLiked)
        items = items.replacingItem(productId: productId, with: optimistic)
        Task {
            do {
                let result = try await productService.toggleLike(productId: productId, isLiked: newLiked)
                await MainActor.run {
                    let count = result.likeCount ?? optimistic.likeCount
                    items = items.replacingItem(productId: productId, with: item.with(likeCount: count, isLiked: result.isLiked))
                }
            } catch {
                await MainActor.run { errorMessage = L10n.userFacingError(error) }
            }
        }
    }
}
