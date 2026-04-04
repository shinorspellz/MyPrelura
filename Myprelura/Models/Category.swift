import Foundation

struct Category: Identifiable, Hashable {
    let id: UUID
    let name: String
    let icon: String
    let color: String
    
    init(id: UUID = UUID(), name: String, icon: String, color: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.color = color
    }
}

extension Category {
    static let clothing = Category(name: "Clothing", icon: "tshirt.fill", color: "#AB28B2")
    static let shoes = Category(name: "Shoes", icon: "shoe.fill", color: "#AB28B2")
    static let accessories = Category(name: "Accessories", icon: "bag.fill", color: "#AB28B2")
    static let electronics = Category(name: "Electronics", icon: "iphone", color: "#AB28B2")
    static let home = Category(name: "Home", icon: "house.fill", color: "#AB28B2")
    static let beauty = Category(name: "Beauty", icon: "sparkles", color: "#AB28B2")
    static let books = Category(name: "Books", icon: "book.fill", color: "#AB28B2")
    static let sports = Category(name: "Sports", icon: "figure.run", color: "#AB28B2")
    
    static let allCategories: [Category] = [
        .clothing,
        .shoes,
        .accessories,
        .electronics,
        .home,
        .beauty,
        .books,
        .sports
    ]
    
    static func fromName(_ name: String) -> Category {
        switch name.lowercased() {
        case "clothing", "clothes":
            return .clothing
        case "shoes", "footwear":
            return .shoes
        case "accessories":
            return .accessories
        case "electronics":
            return .electronics
        case "home":
            return .home
        case "beauty":
            return .beauty
        case "books":
            return .books
        case "sports":
            return .sports
        default:
            return .clothing
        }
    }
}
