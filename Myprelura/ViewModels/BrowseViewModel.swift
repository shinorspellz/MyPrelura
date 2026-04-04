import Foundation
import SwiftUI
import Combine

@MainActor
class BrowseViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published var filteredItems: [Item] = []
    @Published var selectedCategory: Category?
    @Published var searchText: String = ""
    @Published var isLoading: Bool = false
    @Published var sortOption: SortOption = .newest
    
    enum SortOption: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case priceLow = "Price: Low to High"
        case priceHigh = "Price: High to Low"
    }
    
    init() {
        loadItems()
    }
    
    func loadItems() {
        isLoading = true
        
        // Simulate loading
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.items = Item.sampleItems
            self.applyFilters()
            self.isLoading = false
        }
    }
    
    func selectCategory(_ category: Category?) {
        selectedCategory = category
        applyFilters()
    }
    
    func setSearchText(_ text: String) {
        searchText = text
        applyFilters()
    }
    
    func setSortOption(_ option: SortOption) {
        sortOption = option
        applyFilters()
    }
    
    private func applyFilters() {
        var filtered = items
        
        // Category filter
        if let category = selectedCategory {
            filtered = filtered.filter { $0.category.id == category.id }
        }
        
        // Search filter
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.description.localizedCaseInsensitiveContains(searchText) ||
                ($0.brand?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        // Sort
        switch sortOption {
        case .newest:
            filtered = filtered.sorted { $0.createdAt > $1.createdAt }
        case .oldest:
            filtered = filtered.sorted { $0.createdAt < $1.createdAt }
        case .priceLow:
            filtered = filtered.sorted { $0.price < $1.price }
        case .priceHigh:
            filtered = filtered.sorted { $0.price > $1.price }
        }
        
        filteredItems = filtered
    }
}
