import Foundation
import SwiftUI
import Combine

/// Sort options for filtered product lists (e.g. category pages).
enum FilteredProductsSortOption: String, CaseIterable {
    case relevance = "Relevance"
    case newestFirst = "Newest First"
    case priceAsc = "Price Ascending"
    case priceDesc = "Price Descending"
}

@MainActor
class FilteredProductsViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var filteredItems: [Item] = []
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var sortOption: FilteredProductsSortOption = .newestFirst {
        didSet { applyFilters() }
    }
    @Published var filterCondition: String? = nil {
        didSet { applyFilters() }
    }
    @Published var filterMinPrice: String = "" {
        didSet { applyFilters() }
    }
    @Published var filterMaxPrice: String = "" {
        didSet { applyFilters() }
    }
    /// Shop All only: selected category pill (Men, Women, Boys, Girls, Toddlers). nil = all.
    @Published var selectedParentCategory: String? = nil
    /// Shop All: when user selects a sub or sub-sub pill, filter by this category id.
    @Published var selectedCategoryId: Int? = nil
    /// Shop All: root categories (Women, Men, Boys, Girls, Toddlers) from API.
    @Published var shopAllRootCategories: [APICategory] = []
    /// Shop All: subcategories of selected parent (row 2).
    @Published var shopAllSubCategories: [APICategory] = []
    /// Shop All: sub-subcategories of selected sub (row 3).
    @Published var shopAllSubSubCategories: [APICategory] = []
    /// Shop All: selected subcategory (for loading sub-sub).
    @Published var selectedSubCategory: APICategory? = nil
    /// Shop by style: selected style filter (StyleEnum raw value, e.g. PARTY_DRESS). nil = all.
    @Published var selectedStyle: String? = nil
    @Published var isLoading: Bool = false
    @Published var isLoadingMore: Bool = false
    @Published var errorMessage: String?
    @Published var hasMorePages: Bool = true
    
    private var productService: ProductService
    private var client: GraphQLClient
    private let filterType: ProductFilterType
    private var currentPage = 1
    private let pageSize = 20
    private let categoriesService = CategoriesService()
    
    init(filterType: ProductFilterType, authService: AuthService? = nil) {
        self.filterType = filterType
        self.client = GraphQLClient()
        
        if let authService = authService, let token = authService.authToken {
            self.client.setAuthToken(token)
        } else if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
        
        self.productService = ProductService(client: self.client)
    }
    
    convenience init(filterType: ProductFilterType, authService: AuthService) {
        self.init(filterType: filterType, authService: authService)
    }
    
    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
        productService.updateAuthToken(token)
    }
    
    func loadData() {
        isLoading = true
        errorMessage = nil
        currentPage = 1
        hasMorePages = true
        
        Task {
            do {
                let products = try await fetchProducts(page: 1)
                var processed = products.excludingVacationModeSellers().excludingSold()
                if case .recentlyViewed = filterType {
                    processed = processed.sorted { $0.createdAt > $1.createdAt }
                }
                await MainActor.run {
                    self.items = processed
                    self.applyFilters()
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
    
    func loadMore() {
        guard !isLoadingMore && hasMorePages else { return }
        isLoadingMore = true
        
        Task {
            do {
                currentPage += 1
                let products = try await fetchProducts(page: currentPage)
                await MainActor.run {
                    self.items.append(contentsOf: products.excludingVacationModeSellers().excludingSold())
                    applyFilters()
                    self.isLoadingMore = false
                    self.hasMorePages = products.count >= pageSize
                }
            } catch {
                await MainActor.run {
                    self.isLoadingMore = false
                }
            }
        }
    }
    
    func refreshAsync() async {
        await MainActor.run {
            isLoading = true
            currentPage = 1
            hasMorePages = true
        }
        
        do {
            let products = try await fetchProducts(page: 1)
            var processed = products.excludingVacationModeSellers().excludingSold()
            if case .recentlyViewed = filterType {
                processed = processed.sorted { $0.createdAt > $1.createdAt }
            }
            await MainActor.run {
                self.items = processed
                applyFilters()
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
    
    private func fetchProducts(page: Int) async throws -> [Item] {
        switch filterType {
        case .onSale:
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                discountPrice: true
            )
        case .shopBargains:
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                maxPrice: 15
            )
        case .recentlyViewed:
            // Fetch recently viewed products from backend (like Flutter)
            if page == 1 {
                return try await productService.getRecentlyViewedProducts()
            } else {
                // Recently viewed doesn't support pagination, return empty for subsequent pages
                return []
            }
        case .brandsYouLove:
            // For now, return all products - this would need brand filtering
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize
            )
        case .byBrand(let brandName):
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                search: brandName
            )
        case .bySize(let sizeName):
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                search: sizeName
            )
        case .byParentCategory(let categoryName):
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                parentCategory: categoryName
            )
        case .tryCartSearch:
            let query = searchText.trimmingCharacters(in: .whitespaces)
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                search: query.isEmpty ? nil : query,
                parentCategory: selectedParentCategory,
                categoryId: selectedCategoryId
            )
        case .shopByStyle:
            let query = searchText.trimmingCharacters(in: .whitespaces)
            return try await productService.getAllProducts(
                pageNumber: page,
                pageCount: pageSize,
                search: query.isEmpty ? nil : query,
                style: selectedStyle
            )
        }
    }
    
    // MARK: - Shop All category hierarchy (All = nil; max 3 rows: main, sub, sub-sub)
    private static let shopAllMainPillOrder = ["Women", "Men", "Boys", "Girls", "Toddlers"]

    func loadShopAllRootCategoriesIfNeeded() {
        guard case .tryCartSearch = filterType, shopAllRootCategories.isEmpty else { return }
        Task {
            do {
                let root = try await categoriesService.fetchCategories(parentId: nil)
                let ordered = root.sorted { a, b in
                    let i1 = Self.shopAllMainPillOrder.firstIndex(of: a.name) ?? Self.shopAllMainPillOrder.count
                    let i2 = Self.shopAllMainPillOrder.firstIndex(of: b.name) ?? Self.shopAllMainPillOrder.count
                    return i1 < i2
                }
                await MainActor.run { shopAllRootCategories = ordered }
            } catch {
                await MainActor.run { shopAllRootCategories = [] }
            }
        }
    }

    /// Select "All": clear category filters and load all products.
    func selectShopAllAll() {
        selectedParentCategory = nil
        selectedCategoryId = nil
        selectedSubCategory = nil
        shopAllSubCategories = []
        shopAllSubSubCategories = []
        loadData()
    }

    /// Select a main pill (e.g. Women). Load subcategories and products for that parent.
    func selectShopAllMain(_ name: String) {
        selectedParentCategory = name
        selectedCategoryId = nil
        selectedSubCategory = nil
        shopAllSubSubCategories = []
        loadData()
        loadShopAllSubCategories(forParent: name)
    }

    /// Load row 2 subcategories for the selected main (by parent name; we need root id).
    func loadShopAllSubCategories(forParent parentName: String) {
        Task {
            do {
                let root = try await categoriesService.fetchCategories(parentId: nil)
                guard let parent = root.first(where: { $0.name == parentName }),
                      let parentId = Int(parent.id) else {
                    await MainActor.run { shopAllSubCategories = [] }
                    return
                }
                let children = try await categoriesService.fetchCategories(parentId: parentId)
                await MainActor.run { shopAllSubCategories = children }
            } catch {
                await MainActor.run { shopAllSubCategories = [] }
            }
        }
    }

    /// Select a sub pill. Filter by this category id; if it has children, also load row 3.
    func selectShopAllSub(_ category: APICategory) {
        selectedSubCategory = category
        guard let catId = Int(category.id) else {
            selectedCategoryId = nil
            shopAllSubSubCategories = []
            loadData()
            return
        }
        selectedCategoryId = catId
        loadData()
        if category.hasChildren == true {
            loadShopAllSubSubCategories(parentId: catId)
        } else {
            shopAllSubSubCategories = []
        }
    }

    /// Load row 3 sub-subcategories.
    func loadShopAllSubSubCategories(parentId: Int) {
        Task {
            do {
                let children = try await categoriesService.fetchCategories(parentId: parentId)
                await MainActor.run { shopAllSubSubCategories = children }
            } catch {
                await MainActor.run { shopAllSubSubCategories = [] }
            }
        }
    }

    /// Select a sub-sub pill (leaf). Filter by this category id.
    func selectShopAllSubSub(_ category: APICategory) {
        selectedCategoryId = Int(category.id)
        loadData()
    }

    /// Toggle like for a product; updates items and filteredItems optimistically then syncs with server.
    func toggleLike(productId: String) {
        guard let idx = items.firstIndex(where: { $0.productId == productId }) else { return }
        let item = items[idx]
        let newLiked = !item.isLiked
        let newCount = item.likeCount + (newLiked ? 1 : -1)
        let optimistic = item.with(likeCount: max(0, newCount), isLiked: newLiked)
        items[idx] = optimistic
        applyFilters()
        Task {
            do {
                let result = try await productService.toggleLike(productId: productId, isLiked: newLiked)
                await MainActor.run {
                    if let i = items.firstIndex(where: { $0.productId == productId }) {
                        let count = result.likeCount ?? items[i].likeCount
                        items[i] = items[i].with(likeCount: count, isLiked: result.isLiked)
                        applyFilters()
                    }
                }
            } catch {
                await MainActor.run {
                    if let i = items.firstIndex(where: { $0.productId == productId }) {
                        items[i] = item
                        applyFilters()
                    }
                }
            }
        }
    }

    private func applyFilters() {
        var result = items
        if case .tryCartSearch = filterType {
            // Server already filtered by searchText; only apply sort/filters here
        } else if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        if let cond = filterCondition {
            result = result.filter { $0.condition.uppercased() == cond.uppercased() }
        }
        let minP = Double(filterMinPrice.replacingOccurrences(of: ",", with: "."))
        let maxP = Double(filterMaxPrice.replacingOccurrences(of: ",", with: "."))
        if let min = minP, min > 0 { result = result.filter { $0.price >= min } }
        if let max = maxP, max > 0 { result = result.filter { $0.price <= max } }
        switch sortOption {
        case .relevance: break
        case .newestFirst: result = result.sorted { $0.createdAt > $1.createdAt }
        case .priceAsc: result = result.sorted { $0.price < $1.price }
        case .priceDesc: result = result.sorted { $0.price > $1.price }
        }
        filteredItems = result
    }
}
