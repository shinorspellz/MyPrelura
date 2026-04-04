import Foundation
import UIKit

/// Local draft for the sell form. Stored on disk (Application Support/PreluraDrafts/{id}/).
struct SellDraft: Identifiable {
    let id: String
    let savedAt: Date
    var title: String
    var description: String
    var category: SellCategoryDraft?
    var brand: String?
    var condition: String?
    var colours: [String]
    var sizeId: Int?
    var sizeName: String?
    var measurements: String?
    var material: String?
    var styles: [String]
    var price: Double?
    var discountPrice: Double?
    var parcelSize: String?
    /// Relative image filenames in the draft folder (e.g. ["0.jpg", "1.jpg"]).
    var imageFileNames: [String]

    /// Codable payload for draft.json (no UIImage).
    struct Payload: Codable {
        let id: String
        let savedAt: Date
        var title: String
        var description: String
        var category: SellCategoryDraft?
        var brand: String?
        var condition: String?
        var colours: [String]
        var sizeId: Int?
        var sizeName: String?
        var measurements: String?
        var material: String?
        var styles: [String]
        var price: Double?
        var discountPrice: Double?
        var parcelSize: String?
        var imageFileNames: [String]
    }

    var payload: Payload {
        Payload(
            id: id,
            savedAt: savedAt,
            title: title,
            description: description,
            category: category,
            brand: brand,
            condition: condition,
            colours: colours,
            sizeId: sizeId,
            sizeName: sizeName,
            measurements: measurements,
            material: material,
            styles: styles,
            price: price,
            discountPrice: discountPrice,
            parcelSize: parcelSize,
            imageFileNames: imageFileNames
        )
    }

    init(
        id: String = UUID().uuidString,
        savedAt: Date = Date(),
        title: String,
        description: String,
        category: SellCategoryDraft?,
        brand: String?,
        condition: String?,
        colours: [String],
        sizeId: Int?,
        sizeName: String?,
        measurements: String?,
        material: String?,
        styles: [String],
        price: Double?,
        discountPrice: Double?,
        parcelSize: String?,
        imageFileNames: [String]
    ) {
        self.id = id
        self.savedAt = savedAt
        self.title = title
        self.description = description
        self.category = category
        self.brand = brand
        self.condition = condition
        self.colours = colours
        self.sizeId = sizeId
        self.sizeName = sizeName
        self.measurements = measurements
        self.material = material
        self.styles = styles
        self.price = price
        self.discountPrice = discountPrice
        self.parcelSize = parcelSize
        self.imageFileNames = imageFileNames
    }

    init(payload: Payload) {
        id = payload.id
        savedAt = payload.savedAt
        title = payload.title
        description = payload.description
        category = payload.category
        brand = payload.brand
        condition = payload.condition
        colours = payload.colours
        sizeId = payload.sizeId
        sizeName = payload.sizeName
        measurements = payload.measurements
        material = payload.material
        styles = payload.styles
        price = payload.price
        discountPrice = payload.discountPrice
        parcelSize = payload.parcelSize
        imageFileNames = payload.imageFileNames
    }
}

/// Codable category snapshot for drafts.
struct SellCategoryDraft: Codable, Equatable {
    let id: String
    let name: String
    let pathNames: [String]
    let pathIds: [String]
    let fullPath: String?
}

extension SellCategory {
    var draftSnapshot: SellCategoryDraft {
        SellCategoryDraft(id: id, name: name, pathNames: pathNames, pathIds: pathIds, fullPath: fullPath)
    }
}

extension SellCategoryDraft {
    var toSellCategory: SellCategory {
        SellCategory(id: id, name: name, pathNames: pathNames, pathIds: pathIds, fullPath: fullPath)
    }
}
