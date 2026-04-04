import Foundation
import SwiftUI
import Combine

@MainActor
class SellViewModel: ObservableObject {
    @Published var isSubmitting: Bool = false
    @Published var submissionSuccess: Bool = false
    @Published var submissionError: String?

    private let productService = ProductService()
    private let fileUploadService = FileUploadService()
    private let materialsService = MaterialsService()

    /// Submit the full listing: upload images, then create product via GraphQL (matches Flutter createProduct flow).
    func submitListing(
        authToken: String?,
        title: String,
        description: String,
        price: Double,
        brand: String,
        condition: String,
        size: String,
        categoryId: String?,
        categoryName: String?,
        images: [UIImage],
        discountPrice: Double? = nil,
        parcelSize: String? = nil,
        colours: [String] = [],
        sizeId: Int? = nil,
        measurements: String? = nil,
        material: String? = nil,
        styles: [String] = []
    ) {
        isSubmitting = true
        submissionError = nil

        Task {
            do {
                guard let catIdStr = categoryId, let categoryIdInt = Int(catIdStr) else {
                    throw NSError(domain: "SellViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please select a category."])
                }

                // Convert images to JPEG data (same as Flutter compression for upload)
                let imageDataList: [Data] = images.compactMap { image in
                    image.jpegData(compressionQuality: 0.85)
                }
                guard imageDataList.count == images.count, !imageDataList.isEmpty else {
                    throw NSError(domain: "SellViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare images."])
                }

                fileUploadService.setAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
                productService.updateAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
                materialsService.setAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))

                // 1. Upload product images (fileType: PRODUCT)
                let imageUrl = try await fileUploadService.uploadProductImages(imageDataList)

                // 2. Resolve brand id (use customBrand if not in list)
                let brandTrimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                let brandId = brandTrimmed.isEmpty ? nil : try? await productService.getBrandId(byName: brandTrimmed)
                let customBrand: String? = (brandId == nil && !brandTrimmed.isEmpty) ? brandTrimmed : nil

                // 3. Resolve material id(s) — we only have one material name
                var materialIds: [Int]? = nil
                if let mat = material, !mat.isEmpty, let mid = try? await materialsService.getMaterialId(byName: mat) {
                    materialIds = [mid]
                }

                // 4. Parcel size enum (Small -> SMALL, etc.)
                let parcelSizeEnum = Self.mapParcelSizeToEnum(parcelSize)

                // 5. Create product
                _ = try await productService.createProduct(
                    name: title,
                    description: description,
                    price: price,
                    imageUrl: imageUrl,
                    categoryId: categoryIdInt,
                    condition: condition.isEmpty ? nil : condition,
                    parcelSize: parcelSizeEnum,
                    discount: discountPrice,
                    color: colours.isEmpty ? nil : colours,
                    brandId: brandId,
                    customBrand: customBrand,
                    materialIds: materialIds,
                    style: styles.first,
                    styles: styles.count > 1 ? Array(styles.prefix(2)) : (styles.isEmpty ? nil : styles),
                    sizeId: sizeId,
                    status: "ACTIVE"
                )

                isSubmitting = false
                submissionSuccess = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                submissionSuccess = false
            } catch {
                isSubmitting = false
                submissionError = (error as NSError).localizedDescription
            }
        }
    }

    /// Update an existing listing. When `newListingImages` is empty, existing photos are unchanged. When non-empty, uploads are appended and the full gallery is sent with `UPDATE_INDEX`.
    func updateListing(
        authToken: String?,
        productId: Int,
        existingImagePairs: [(url: String, thumbnail: String)],
        title: String,
        description: String,
        price: Double,
        brand: String,
        condition: String,
        size: String,
        categoryId: String?,
        categoryName: String?,
        newListingImages: [UIImage],
        discountPrice: Double? = nil,
        parcelSize: String? = nil,
        colours: [String] = [],
        sizeId: Int? = nil,
        measurements: String? = nil,
        material: String? = nil,
        styles: [String] = []
    ) {
        isSubmitting = true
        submissionError = nil
        Task {
            do {
                guard let catIdStr = categoryId, let categoryIdInt = Int(catIdStr) else {
                    throw NSError(domain: "SellViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please select a category."])
                }
                fileUploadService.setAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
                productService.updateAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
                materialsService.setAuthToken(authToken ?? UserDefaults.standard.string(forKey: "AUTH_TOKEN"))

                let brandTrimmed = brand.trimmingCharacters(in: .whitespacesAndNewlines)
                let brandId = brandTrimmed.isEmpty ? nil : try? await productService.getBrandId(byName: brandTrimmed)
                let customBrand: String? = (brandId == nil && !brandTrimmed.isEmpty) ? brandTrimmed : nil

                var materialIds: [Int]? = nil
                if let mat = material, !mat.isEmpty, let mid = try? await materialsService.getMaterialId(byName: mat) {
                    materialIds = [mid]
                }

                let parcelSizeEnum = Self.mapParcelSizeToEnum(parcelSize)

                var imagePairs: [(url: String, thumbnail: String)]? = nil
                var imageAction: String? = nil
                if !newListingImages.isEmpty {
                    let imageDataList: [Data] = newListingImages.compactMap { $0.jpegData(compressionQuality: 0.85) }
                    guard imageDataList.count == newListingImages.count else {
                        throw NSError(domain: "SellViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to prepare images."])
                    }
                    let uploaded = try await fileUploadService.uploadProductImages(imageDataList)
                    let combined = existingImagePairs + uploaded
                    imagePairs = combined
                    imageAction = "UPDATE_INDEX"
                }

                try await productService.updateProduct(
                    productId: productId,
                    name: title,
                    description: description,
                    price: price,
                    categoryId: categoryIdInt,
                    condition: condition.isEmpty ? nil : condition,
                    parcelSize: parcelSizeEnum,
                    discountSalePrice: discountPrice,
                    color: colours.isEmpty ? nil : colours,
                    brandId: brandId,
                    customBrand: customBrand,
                    materialIds: materialIds,
                    style: styles.first,
                    styles: styles.count > 1 ? Array(styles.prefix(2)) : (styles.isEmpty ? nil : styles),
                    sizeId: sizeId,
                    imagePairs: imagePairs,
                    imageAction: imageAction
                )

                isSubmitting = false
                submissionSuccess = true
                try? await Task.sleep(nanoseconds: 500_000_000)
                submissionSuccess = false
            } catch {
                isSubmitting = false
                submissionError = (error as NSError).localizedDescription
            }
        }
    }

    /// Maps UI parcel size to backend ParcelSizeEnum. Backend only supports SMALL, MEDIUM, LARGE.
    private static func mapParcelSizeToEnum(_ value: String?) -> String? {
        guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        switch v.lowercased() {
        case "small": return "SMALL"
        case "medium": return "MEDIUM"
        case "large", "extra large": return "LARGE"
        default: return "LARGE"
        }
    }
}
