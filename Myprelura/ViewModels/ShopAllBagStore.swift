import Combine
import Foundation
import SwiftUI

/// Bag for Shop All (Try Cart): holds items added via "Add to bag". Used for floating total and checkout.
final class ShopAllBagStore: ObservableObject {
    @Published private(set) var items: [Item] = []

    var totalPrice: Double {
        items.reduce(0) { $0 + $1.price }
    }

    var formattedTotal: String {
        CurrencyFormatter.gbp(totalPrice)
    }

    func add(_ item: Item) {
        items.append(item)
    }

    func remove(_ item: Item) {
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items.remove(at: idx)
        }
    }

    /// Remove one occurrence at index (for list display).
    func remove(at index: Int) {
        guard index >= 0, index < items.count else { return }
        items.remove(at: index)
    }

    func remove(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
    }

    func clear() {
        items = []
    }
}
