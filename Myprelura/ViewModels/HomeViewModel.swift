import Foundation
import SwiftUI
import Combine

@MainActor
class HomeViewModel: ObservableObject {
    @Published var allItems: [Item] = []
    @Published var filteredItems: [Item] = []
    @Published var searchText: String = ""
    @Published var selectedCategory: String = "All"
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var hasMorePages: Bool = true
    /// When AI search mapped a colour alias (e.g. "camo" → "Green"), show this hint.
    @Published var searchClosestMatchHint: String?
    
    private let productService = ProductService()
    private var currentPage = 1
    private let pageSize = 20

    func updateAuthToken(_ token: String?) {
        productService.updateAuthToken(token)
    }
    
    init() {
        loadData()
    }

    /// Toggle like for a product and update local state. Applies optimistic update so the heart/count change immediately on tap.
    func toggleLike(productId: String) {
        guard !productId.isEmpty, let item = allItems.first(where: { $0.productId == productId }) else { return }
        let newLiked = !item.isLiked
        let newCount = item.likeCount + (newLiked ? 1 : -1)
        let optimistic = item.with(likeCount: max(0, newCount), isLiked: newLiked)
        if let i = allItems.firstIndex(where: { $0.productId == productId }) {
            allItems[i] = optimistic
        }
        if let j = filteredItems.firstIndex(where: { $0.productId == productId }) {
            filteredItems[j] = optimistic
        }
        Task {
            do {
                let result = try await productService.toggleLike(productId: productId, isLiked: newLiked)
                await MainActor.run {
                    let count = result.likeCount ?? optimistic.likeCount
                    let updated = item.with(likeCount: count, isLiked: result.isLiked)
                    if let i = allItems.firstIndex(where: { $0.productId == productId }) {
                        allItems[i] = updated
                    }
                    if let j = filteredItems.firstIndex(where: { $0.productId == productId }) {
                        filteredItems[j] = updated
                    }
                }
            } catch {
                await MainActor.run {
                    // Keep optimistic state so the heart doesn't flip back; surface error for user
                    errorMessage = L10n.userFacingError(error)
                }
            }
        }
    }
    
    func loadData() {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMorePages = true
        
        Task {
            do {
                // Use the current selectedCategory value
                let categoryFilter = selectedCategory == "All" ? nil : selectedCategory
                let products = try await productService.getAllProducts(
                    pageNumber: currentPage,
                    pageCount: pageSize,
                    parentCategory: categoryFilter
                )
                await MainActor.run {
                    let visible = products.excludingVacationModeSellers().excludingSold()
                    self.allItems = visible
                    self.filteredItems = visible
                    self.isLoading = false
                    self.hasMorePages = products.count >= pageSize
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = L10n.userFacingError(error)
                    print("❌ Error loading products: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func loadMore() {
        guard !isLoadingMore && hasMorePages else { return }
        
        isLoadingMore = true
        currentPage += 1
        
        Task {
            do {
                let products = try await productService.getAllProducts(
                    pageNumber: currentPage,
                    pageCount: pageSize,
                    search: searchText.isEmpty ? nil : searchText,
                    parentCategory: selectedCategory
                )
                await MainActor.run {
                    let visible = products.excludingVacationModeSellers().excludingSold().excludingSold()
                    self.allItems.append(contentsOf: visible)
                    self.filteredItems.append(contentsOf: visible)
                    self.isLoadingMore = false
                    self.hasMorePages = products.count >= pageSize
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMore = false
                    self.currentPage -= 1 // Revert page increment on error
                    print("❌ Load more error: \(error.localizedDescription)")
                }
            }
        }
    }
    
    func searchItems(query: String) {
        searchText = query
        searchClosestMatchHint = nil
        runSearch(search: query.isEmpty ? nil : query, category: selectedCategory)
    }
    
    /// Run search using AI-parsed result (colours/categories resolved; hint for "closest to").
    func searchWithParsed(_ parsed: ParsedSearch) {
        searchText = parsed.searchText
        searchClosestMatchHint = parsed.closestMatchHint
        if let cat = parsed.categoryOverride, !cat.isEmpty {
            selectedCategory = cat
        }
        let categoryFilter = selectedCategory == "All" ? nil : selectedCategory
        runSearch(search: parsed.searchText.isEmpty ? nil : parsed.searchText, category: categoryFilter ?? selectedCategory)
    }
    
    private func runSearch(search: String?, category: String?) {
        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil
        let categoryFilter = (category == "All" || category == nil) ? nil : category
        
        Task {
            do {
                let products = try await productService.getAllProducts(
                    pageNumber: currentPage,
                    pageCount: pageSize,
                    search: search,
                    parentCategory: categoryFilter
                )
                await MainActor.run {
                    let visible = products.excludingVacationModeSellers().excludingSold()
                    self.allItems = visible
                    self.filteredItems = visible
                    self.isLoading = false
                    self.hasMorePages = products.count >= pageSize
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = L10n.userFacingError(error)
                }
            }
        }
    }
    
    func filterByCategory(_ category: String) {
        selectedCategory = category
        // Reload data with new category filter
        currentPage = 1
        hasMorePages = true
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                // Use the current selectedCategory value (convert "All" to nil)
                let categoryFilter = selectedCategory == "All" ? nil : selectedCategory
                let products = try await productService.getAllProducts(
                    pageNumber: currentPage,
                    pageCount: pageSize,
                    parentCategory: categoryFilter
                )
                await MainActor.run {
                    let visible = products.excludingVacationModeSellers().excludingSold()
                    self.allItems = visible
                    self.filteredItems = visible
                    self.isLoading = false
                    self.hasMorePages = products.count >= pageSize
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    self.errorMessage = L10n.userFacingError(error)
                    print("❌ Error filtering by category '\(category)': \(error.localizedDescription)")
                }
            }
        }
    }
    
    func refresh() {
        currentPage = 1
        loadData()
    }
    
    func refreshAsync() async {
        await MainActor.run {
            currentPage = 1
            hasMorePages = true
            isLoading = true
            errorMessage = nil
        }
        
        do {
            let products = try await productService.getAllProducts(
                pageNumber: 1,
                pageCount: pageSize,
                search: searchText.isEmpty ? nil : searchText,
                parentCategory: selectedCategory == "All" ? nil : selectedCategory
            )
            
            await MainActor.run {
                let visible = products.excludingVacationModeSellers().excludingSold()
                self.allItems = visible
                self.filteredItems = visible
                self.isLoading = false
                self.hasMorePages = products.count >= pageSize
            }
        } catch {
            await MainActor.run {
                self.isLoading = false
                self.errorMessage = L10n.userFacingError(error)
            }
        }
    }
    
    private func applyFilters() {
        // This is now handled by reloading from API with filters
        // Keeping for backward compatibility but filters are applied server-side
        var filtered = allItems
        
        // Search filter - use GraphQL search parameter
        if !searchText.isEmpty {
            Task {
                do {
                    let searchResults = try await productService.getAllProducts(
                        pageNumber: 1,
                        pageCount: pageSize,
                        search: searchText,
                        parentCategory: selectedCategory
                    )
                    await MainActor.run {
                        self.filteredItems = searchResults.excludingVacationModeSellers().excludingSold()
                    }
                } catch {
                    await MainActor.run {
                        print("❌ Search error: \(error.localizedDescription)")
                        // Fallback to client-side filtering
                        filtered = filtered.filter {
                            $0.title.localizedCaseInsensitiveContains(searchText) ||
                            $0.description.localizedCaseInsensitiveContains(searchText) ||
                            ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
                        }
                        self.filteredItems = filtered
                    }
                }
            }
        } else {
            filteredItems = filtered
        }
    }
}
