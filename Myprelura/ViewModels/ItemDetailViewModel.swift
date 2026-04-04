import Foundation
import SwiftUI
import Combine

@MainActor
class ItemDetailViewModel: ObservableObject {
    @Published var similarItems: [Item] = []
    @Published var memberItems: [Item] = []
    @Published var isLoadingSimilar: Bool = false
    @Published var isLoadingMember: Bool = false
    @Published var isLiked: Bool = false
    @Published var likeCount: Int = 0
    @Published var errorMessage: String?
    /// Current user's profile picture URL; used when viewing own product and seller avatar is missing.
    @Published var currentUserAvatarURL: String?
    
    var productService: ProductService
    private var userService: UserService
    private var client: GraphQLClient
    
    init(authService: AuthService? = nil) {
        self.client = GraphQLClient()
        
        if let authService = authService, let token = authService.authToken {
            self.client.setAuthToken(token)
        } else if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
        
        self.productService = ProductService(client: self.client)
        self.userService = UserService(client: self.client)
    }
    
    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
        productService.updateAuthToken(token)
        userService.updateAuthToken(token)
    }
    
    func loadSimilarProducts(productId: String, categoryId: Int? = nil) {
        isLoadingSimilar = true
        errorMessage = nil
        
        Task {
            do {
                let products = try await productService.getSimilarProducts(
                    productId: productId,
                    categoryId: categoryId
                )
                await MainActor.run {
                    self.similarItems = products
                    self.isLoadingSimilar = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingSimilar = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// - Parameter includeInListIfEmpty: When non-nil (e.g. viewing own listing), if the API returns no other items, this item is shown so "Member's items" is not empty (e.g. right after posting).
    func loadMemberItems(username: String, excludeProductId: UUID, includeInListIfEmpty: Item? = nil) {
        isLoadingMember = true
        errorMessage = nil
        
        Task {
            do {
                let products = try await userService.getUserProducts(username: username)
                await MainActor.run {
                    // Exclude the current product from the list
                    var list = products.filter { $0.id != excludeProductId }
                    // If empty and we have a fallback (e.g. own just-posted item), show it so the section isn’t empty
                    if list.isEmpty, let fallback = includeInListIfEmpty {
                        list = [fallback]
                    }
                    self.memberItems = list
                    self.isLoadingMember = false
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMember = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
    
    /// Sync like state from the item (call from view onAppear).
    func syncLikeState(isLiked: Bool, likeCount: Int) {
        self.isLiked = isLiked
        self.likeCount = likeCount
    }
    
    /// Load current user's profile picture URL (for own product detail when seller avatar is missing).
    func loadCurrentUserAvatar() async {
        do {
            let user = try await userService.getUser()
            currentUserAvatarURL = user.avatarURL
        } catch {
            currentUserAvatarURL = nil
        }
    }

    /// Record this product as recently viewed (fire-and-forget). Call when product detail is shown.
    func recordRecentlyViewed(productId: String?) {
        guard let productId = productId, let productIdInt = Int(productId) else { return }
        Task {
            await productService.addToRecentlyViewed(productId: productIdInt)
            await MainActor.run {
                NotificationCenter.default.post(name: .preluraRecentlyViewedDidUpdate, object: nil)
            }
        }
    }
    
    func toggleLike(productId: String) {
        // Optimistic update so heart changes immediately
        let newLiked = !isLiked
        let newCount = likeCount + (newLiked ? 1 : -1)
        isLiked = newLiked
        likeCount = max(0, newCount)
        Task {
            do {
                let result = try await productService.toggleLike(productId: productId, isLiked: newLiked)
                await MainActor.run {
                    self.isLiked = result.isLiked
                    if let count = result.likeCount { self.likeCount = count }
                }
            } catch {
                await MainActor.run {
                    // Keep optimistic state so the heart doesn't flip back
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Delete own listing. Call from product options. On success, post profile refresh.
    func deleteProduct(productId: String) async throws {
        guard let id = Int(productId) else { return }
        try await productService.deleteProduct(productId: id)
        await MainActor.run {
            NotificationCenter.default.post(name: .preluraUserProfileDidUpdate, object: nil)
        }
    }

    /// Mark own listing as sold. Call from product options. On success, post profile refresh.
    func markAsSold(productId: String) async throws {
        guard let id = Int(productId) else { return }
        try await productService.updateProductStatus(productId: id, status: "SOLD")
        await MainActor.run {
            NotificationCenter.default.post(name: .preluraUserProfileDidUpdate, object: nil)
        }
    }

    /// Refetch a single product by ID (e.g. after marking as sold). Returns updated Item or nil.
    func loadProduct(productId: String) async -> Item? {
        guard let id = Int(productId) else { return nil }
        do {
            return try await productService.getProduct(id: id)
        } catch {
            return nil
        }
    }
}
