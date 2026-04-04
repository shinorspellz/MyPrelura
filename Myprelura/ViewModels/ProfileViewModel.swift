import Foundation
import SwiftUI
import Combine
import UIKit

@MainActor
class ProfileViewModel: ObservableObject {
    @Published var user: User?
    @Published var userItems: [Item] = []
    @Published var isMenuVisible: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    var topBrands: [String] {
        // Extract unique brands from userItems, sorted by frequency then by name so order is stable when view re-renders.
        let brandCounts = Dictionary(grouping: userItems.compactMap { $0.brand }, by: { $0 })
            .mapValues { $0.count }
            .sorted { a, b in
                if a.value != b.value { return a.value > b.value }
                return a.key.localizedCompare(b.key) == .orderedAscending
            }
        return Array(brandCounts.prefix(10).map { $0.key })
    }
    
    var categoriesWithCounts: [(name: String, count: Int)] {
        // Group items by actual category name from API (subcategories like "Blouses", "Dresses", etc.)
        // Use categoryName if available, otherwise fall back to category.name
        let categoryCounts = Dictionary(grouping: userItems, by: { $0.categoryName ?? $0.category.name })
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.name < $1.name }
        
        return categoryCounts
    }
    
    private var userService: UserService
    private var productService: ProductService
    private var fileUploadService: FileUploadService
    private var client: GraphQLClient

    @Published var isUploadingProfilePhoto: Bool = false
    @Published var profilePhotoUploadError: String?

    init(authService: AuthService? = nil) {
        // Create services with shared client that has auth token
        self.client = GraphQLClient()
        // Get token from authService or UserDefaults
        if let authService = authService, let token = authService.authToken {
            self.client.setAuthToken(token)
        } else if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
        self.userService = UserService(client: self.client)
        self.productService = ProductService(client: self.client)
        self.fileUploadService = FileUploadService()
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.fileUploadService.setAuthToken(token)
        }
        // Don't load in init - will be called from view
    }

    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
        userService.updateAuthToken(token)
        productService.updateAuthToken(token)
        fileUploadService.setAuthToken(token)
    }
    
    func loadUserData() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        
        do {
            // Load user profile and products in parallel for faster display
            async let userTask = userService.getUser()
            async let productsTask = userService.getUserProducts()
            let (fetchedUser, products) = try await (userTask, productsTask)
            await MainActor.run {
                self.user = fetchedUser
                self.userItems = products
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = L10n.userFacingError(error)
                print("❌ Profile load error: \(error.localizedDescription)")
                print("❌ Error details: \(error)")
                if let graphQLError = error as? GraphQLError {
                    print("❌ GraphQL Error: \(graphQLError)")
                }
            }
        }
    }
    
    func refresh() {
        Task {
            await loadUserData()
        }
    }
    
    func refreshAsync() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
            // Keep user and userItems so the UI doesn't flash to empty/shimmer and break layout
        }
        await loadUserData()
    }

    /// Toggle like for a product and update userItems. Optimistic update so heart doesn't flip back on API failure.
    func toggleLike(productId: String) {
        guard !productId.isEmpty, let item = userItems.first(where: { $0.productId == productId }) else { return }
        let newLiked = !item.isLiked
        let newCount = item.likeCount + (newLiked ? 1 : -1)
        let optimistic = item.with(likeCount: max(0, newCount), isLiked: newLiked)
        userItems = userItems.replacingItem(productId: productId, with: optimistic)
        Task {
            do {
                let result = try await productService.toggleLike(productId: productId, isLiked: newLiked)
                await MainActor.run {
                    let count = result.likeCount ?? optimistic.likeCount
                    userItems = userItems.replacingItem(productId: productId, with: item.with(likeCount: count, isLiked: result.isLiked))
                }
            } catch {
                await MainActor.run { errorMessage = L10n.userFacingError(error) }
            }
        }
    }
    
    func toggleMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isMenuVisible.toggle()
        }
    }
    
    func hideMenu() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isMenuVisible = false
        }
    }
    
    /// Uploads profile photo to backend (GraphQL UploadFile + updateProfile) and refreshes user. No local storage — avatar is always from backend.
    /// Pass current authToken so the upload uses the latest token (e.g. after refresh).
    func uploadProfileImage(_ image: UIImage, authToken: String?) {
        let resized = Self.resizeForProfileUpload(image, maxLongSide: 1200)
        guard let jpegData = resized.jpegData(compressionQuality: 0.85) else {
            profilePhotoUploadError = "Could not prepare image"
            return
        }
        profilePhotoUploadError = nil
        isUploadingProfilePhoto = true
        fileUploadService.setAuthToken(authToken)
        Task {
            do {
                let (url, thumbnail) = try await fileUploadService.uploadProfileImage(jpegData)
                try await userService.updateProfilePicture(profilePictureUrl: url, thumbnailUrl: thumbnail)
                await loadUserData()
            } catch {
                await MainActor.run {
                    profilePhotoUploadError = L10n.userFacingError(error)
                }
            }
            await MainActor.run {
                isUploadingProfilePhoto = false
            }
        }
    }

    /// Resize image so longest side is at most maxLongSide; avoids oversized uploads and backend rejections.
    private static func resizeForProfileUpload(_ image: UIImage, maxLongSide: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxLongSide || size.height > maxLongSide else { return image }
        let scale = min(maxLongSide / size.width, maxLongSide / size.height)
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
