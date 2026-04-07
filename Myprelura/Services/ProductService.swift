import Foundation
import Combine

@MainActor
class ProductService: ObservableObject {
    private var client: GraphQLClient
    
    init(client: GraphQLClient? = nil) {
        if let client = client {
            self.client = client
        } else {
            self.client = GraphQLClient()
            // Try to load auth token from UserDefaults
            if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
                self.client.setAuthToken(token)
            }
        }
    }
    
    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }
    
    func getAllProducts(pageNumber: Int = 1, pageCount: Int = 20, search: String? = nil, parentCategory: String? = nil, categoryId: Int? = nil, discountPrice: Bool? = nil, minPrice: Double? = nil, maxPrice: Double? = nil, style: String? = nil) async throws -> [Item] {
        let query = """
        query AllProducts($pageNumber: Int, $pageCount: Int, $search: String, $filters: ProductFiltersInput) {
          allProducts(pageNumber: $pageNumber, pageCount: $pageCount, search: $search, filters: $filters) {
            id
            listingCode
            name
            description
            price
            discountPrice
            imagesUrl
            condition
            createdAt
            size {
              id
              name
            }
            brand {
              id
              name
            }
            customBrand
            likes
            views
            userLiked
            seller {
              id
              username
              displayName
              profilePictureUrl
              isVacationMode
              meta
            }
            category {
              id
              name
            }
            color
            status
          }
          allProductsTotalNumber
        }
        """
        
        var variables: [String: Any] = [
            "pageNumber": pageNumber,
            "pageCount": pageCount
        ]
        
        if let search = search, !search.isEmpty {
            variables["search"] = search
        }
        
        // Build filters object
        var filters: [String: Any] = [:]
        if let parentCategory = parentCategory, parentCategory != "All" {
            // Map category names to GraphQL enum values
            if let categoryEnum = mapCategoryToEnum(parentCategory) {
                filters["parentCategory"] = categoryEnum
            }
        }
        if let categoryId = categoryId {
            filters["category"] = categoryId
        }
        
        // Add discountPrice filter if specified (like Flutter app)
        if let discountPrice = discountPrice {
            filters["discountPrice"] = discountPrice
        }
        
        // Add minPrice / maxPrice filters if specified (ProductFiltersInput)
        if let minPrice = minPrice {
            filters["minPrice"] = minPrice
        }
        if let maxPrice = maxPrice {
            filters["maxPrice"] = maxPrice
        }
        if let style = style, !style.isEmpty {
            filters["style"] = style
        }
        
        if !filters.isEmpty {
            variables["filters"] = filters
        }
        
        let response: AllProductsResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: AllProductsResponse.self
        )
        
        guard let products = response.allProducts else {
            return []
        }
        return itemsFromProductData(products)
    }

    /// Map GraphQL ProductData array to [Item]. Reused by getAllProducts, filterProductsByPrice, getFavoriteBrandProducts.
    private func itemsFromProductData(_ products: [ProductData]) -> [Item] {
        products.compactMap { product in
            let idString: String
            if let anyCodable = product.id {
                if let intValue = anyCodable.value as? Int {
                    idString = String(intValue)
                } else if let stringValue = anyCodable.value as? String {
                    idString = stringValue
                } else {
                    idString = String(describing: anyCodable.value)
                }
            } else {
                return nil
            }
            let imageURLs = extractImageURLs(from: product.imagesUrl)
            let listDisplayURL = ProductListImageURL.preferredString(fromImagesUrlArray: product.imagesUrl) ?? imageURLs.first
            let sellerIdString: String
            let sellerUserIdInt: Int?
            if let sellerId = product.seller?.id {
                if let intValue = sellerId.value as? Int {
                    sellerIdString = String(intValue)
                    sellerUserIdInt = intValue
                } else if let stringValue = sellerId.value as? String {
                    sellerIdString = stringValue
                    sellerUserIdInt = Int(stringValue)
                } else {
                    sellerIdString = String(describing: sellerId.value)
                    sellerUserIdInt = nil
                }
            } else {
                sellerIdString = ""
                sellerUserIdInt = nil
            }
            let resolvedNumericSellerId: Int? = sellerUserIdInt ?? Int(sellerIdString.trimmingCharacters(in: .whitespacesAndNewlines))
            let sellerUUID: UUID = {
                if let n = resolvedNumericSellerId {
                    return User.stableIdForSeller(backendUserId: n)
                }
                if let u = UUID(uuidString: sellerIdString) { return u }
                let seed = (product.seller?.username ?? "") + "|" + sellerIdString
                var h: UInt64 = 5381
                for b in seed.utf8 { h = ((h << 5) &+ h) &+ UInt64(b) }
                let narrowed = Int(truncatingIfNeeded: h & 0x7fff_fffe)
                return User.stableIdForSeller(backendUserId: narrowed == 0 ? 1 : narrowed)
            }()
            let originalPrice = product.price ?? 0.0
            let discountPercentage: Double? = {
                guard let discountPriceStr = product.discountPrice,
                      let discount = Double(discountPriceStr),
                      discount > 0 else { return nil }
                return discount
            }()
            let finalPrice: Double
            let itemOriginalPrice: Double?
            if let discount = discountPercentage {
                finalPrice = originalPrice - (originalPrice * discount / 100)
                itemOriginalPrice = originalPrice
            } else {
                finalPrice = originalPrice
                itemOriginalPrice = nil
            }
            let listingCode: String? = {
                guard let lc = product.listingCode?.trimmingCharacters(in: .whitespacesAndNewlines), !lc.isEmpty else { return nil }
                return lc
            }()
            return Item(
                id: Item.id(fromProductId: idString),
                productId: idString,
                listingCode: listingCode,
                title: product.name ?? "",
                description: product.description ?? "",
                price: finalPrice,
                originalPrice: itemOriginalPrice,
                imageURLs: imageURLs,
                listDisplayImageURL: listDisplayURL,
                category: Category.fromName(product.category?.name ?? ""),
                categoryName: product.category?.name,
                seller: User(
                    id: sellerUUID,
                    userId: resolvedNumericSellerId,
                    username: product.seller?.username ?? "",
                    displayName: product.seller?.displayName ?? "",
                    avatarURL: product.seller?.profilePictureUrl,
                    isVacationMode: product.seller?.isVacationMode ?? false,
                    postageOptions: SellerPostageOptions.from(decoded: product.seller?.meta?.value?.postage)
                ),
                condition: product.condition ?? "",
                size: product.size?.name,
                brand: product.brand?.name ?? product.customBrand,
                colors: product.color ?? [],
                likeCount: product.likes ?? 0,
                views: product.views ?? 0,
                createdAt: Self.parseCreatedAt(product.createdAt) ?? Date(),
                isLiked: product.userLiked ?? false,
                status: product.status ?? "ACTIVE",
                sellCategoryBackendId: Self.graphQLStringId(product.category?.id),
                sellSizeBackendId: Self.graphQLIntId(product.size?.id)
            )
        }
    }
    
    private static func parseCreatedAt(_ iso8601: String?) -> Date? {
        guard let s = iso8601 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: s) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: s)
    }
    
    private func extractImageURLs(from imagesUrl: [String]?) -> [String] {
        guard let imagesUrl = imagesUrl else { return [] }
        var urls: [String] = []
        for imageJson in imagesUrl {
            // imagesUrl contains JSON strings like '{"url":"...","thumbnail":"..."}'
            // Try to parse as JSON string
            if let data = imageJson.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let url = json["url"] as? String, !url.isEmpty {
                        urls.append(url)
                    }
                } catch {
                    // If JSON parsing fails, try using the string directly as URL (fallback)
                    // This handles cases where imagesUrl might already contain direct URLs
                    if !imageJson.isEmpty && (imageJson.hasPrefix("http://") || imageJson.hasPrefix("https://")) {
                        urls.append(imageJson)
                    }
                }
            } else {
                // If data conversion fails, try using the string directly as URL (fallback)
                if !imageJson.isEmpty && (imageJson.hasPrefix("http://") || imageJson.hasPrefix("https://")) {
                    urls.append(imageJson)
                }
            }
        }
        return urls
    }
    
    func searchProducts(query: String, pageNumber: Int = 1, pageCount: Int = 20) async throws -> [Item] {
        // Use the search parameter in getAllProducts
        return try await getAllProducts(pageNumber: pageNumber, pageCount: pageCount, search: query)
    }

    /// Products filtered by max price. Matches Flutter filterProductByPrice(priceLimit). Auth not required.
    func filterProductsByPrice(priceLimit: Double, pageNumber: Int = 1, pageCount: Int = 20) async throws -> [Item] {
        let query = """
        query FilterProductsByPrice($priceLimit: Float!, $pageCount: Int, $pageNumber: Int) {
          filterProductsByPrice(priceLimit: $priceLimit, pageCount: $pageCount, pageNumber: $pageNumber) {
            id listingCode name description price discountPrice imagesUrl condition createdAt
            size { id name }
            brand { id name }
            customBrand likes views userLiked
            seller { id username displayName profilePictureUrl isVacationMode meta }
            category { id name }
            color status
          }
        }
        """
        let variables: [String: Any] = ["priceLimit": priceLimit, "pageNumber": pageNumber, "pageCount": pageCount]
        struct Payload: Decodable { let filterProductsByPrice: [ProductData]? }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return itemsFromProductData(response.filterProductsByPrice ?? [])
    }

    /// User's products grouped by category/brand (for profile shop). Matches Flutter getUserProductGrouping(userId, groupBy). Auth required.
    func getUserProductGrouping(userId: Int, groupBy: String) async throws -> [CategoryGroup] {
        let query = """
        query UserProductGrouping($userId: Int!, $groupBy: ProductGroupingEnum!) {
          userProductGrouping(userId: $userId, groupBy: $groupBy) {
            id name count
          }
        }
        """
        let variables: [String: Any] = ["userId": userId, "groupBy": groupBy]
        struct Payload: Decodable {
            let userProductGrouping: [CategoryGroupRow]?
        }
        struct CategoryGroupRow: Decodable {
            let id: Int?
            let name: String?
            let count: Int?
        }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return (response.userProductGrouping ?? []).map { row in
            CategoryGroup(id: row.id ?? 0, name: row.name ?? "", count: row.count ?? 0)
        }
    }

    /// Products from the user's favorite brands. Matches Flutter getFavoriteBrandProducts(top). Auth required.
    func getFavoriteBrandProducts(top: Int = 20) async throws -> [Item] {
        let query = """
        query FavoriteBrandProducts($top: Int!) {
          favoriteBrandProducts(top: $top) {
            id listingCode name description price discountPrice imagesUrl condition createdAt
            size { id name }
            brand { id name }
            customBrand likes views userLiked
            seller { id username displayName profilePictureUrl isVacationMode meta }
            category { id name }
            color status
          }
        }
        """
        let variables: [String: Any] = ["top": top]
        struct Payload: Decodable { let favoriteBrandProducts: [ProductData]? }
        let response: Payload = try await client.execute(query: query, variables: variables, responseType: Payload.self)
        return itemsFromProductData(response.favoriteBrandProducts ?? [])
    }

    /// One page for the sell-flow brand picker (infinite scroll). `totalCount` is rows matching `search` (or all brands if `search` is nil).
    func getBrandsPage(search: String?, pageNumber: Int, pageCount: Int = 80) async throws -> (names: [String], totalCount: Int?) {
        let (names, totalNumber) = try await fetchBrandsPage(search: search, pageNumber: pageNumber, pageCount: pageCount)
        return (names: names, totalCount: totalNumber)
    }

    /// Fetches the full brand list (many sequential requests). Prefer `getBrandsPage` + infinite scroll in UI.
    func getBrandNames() async throws -> [String] {
        let pageCount = 250
        var page = 1
        var collected: [String] = []
        var reportedTotal: Int?
        while true {
            let (pageNames, totalOpt) = try await fetchBrandsPage(search: nil, pageNumber: page, pageCount: pageCount)
            if let t = totalOpt { reportedTotal = t }
            collected.append(contentsOf: pageNames)
            if pageNames.count < pageCount { break }
            if let t = reportedTotal, collected.count >= t { break }
            page += 1
            if page > 200 { break }
        }
        var seen = Set<String>()
        var unique: [String] = []
        for n in collected {
            let t = n.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty, seen.insert(t.lowercased()).inserted else { continue }
            unique.append(t)
        }
        return unique.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Fetch a single page of brands (for search). Matches Flutter getBrands(search: query).
    func getBrandNames(search: String, pageNumber: Int = 1, pageCount: Int = 50) async throws -> [String] {
        let (names, _) = try await fetchBrandsPage(search: search, pageNumber: pageNumber, pageCount: pageCount)
        return names
    }

    /// Single page of brands — matches Flutter ProductRepo.getBrands / query Brands (search, pageNumber, pageCount).
    private func fetchBrandsPage(search: String?, pageNumber: Int, pageCount: Int) async throws -> (names: [String], totalNumber: Int?) {
        let query = """
        query Brands($search: String, $pageCount: Int, $pageNumber: Int) {
          brands(search: $search, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            name
          }
          brandsTotalNumber
        }
        """
        var variables: [String: Any] = ["pageCount": pageCount, "pageNumber": pageNumber]
        if let search = search, !search.isEmpty { variables["search"] = search }
        struct BrandsResponse: Decodable {
            let brands: [BrandRow]?
            let brandsTotalNumber: Int?
        }
        struct BrandRow: Decodable {
            let id: Int?
            let name: String?
        }
        let response: BrandsResponse = try await client.execute(query: query, variables: variables, responseType: BrandsResponse.self)
        let names = (response.brands ?? []).compactMap { $0.name }.filter { !$0.isEmpty }
        return (names, response.brandsTotalNumber)
    }

    /// Resolve brand name to backend brand id (for CreateProduct). Fetches one page of brands and finds first match by name.
    func getBrandId(byName name: String) async throws -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        struct BrandsResponse: Decodable {
            let brands: [BrandRow]?
        }
        struct BrandRow: Decodable {
            let id: Int?
            let name: String?
        }
        let query = """
        query Brands($search: String, $pageCount: Int, $pageNumber: Int) {
          brands(search: $search, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            name
          }
        }
        """
        let response: BrandsResponse = try await client.execute(
            query: query,
            variables: ["search": trimmed, "pageCount": 50, "pageNumber": 1],
            responseType: BrandsResponse.self
        )
        let match = (response.brands ?? []).first { ($0.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() }
        return match?.id
    }

    /// Create a product (listing). Upload images first via FileUploadService.uploadProductImages, then call this with the returned imageUrl list.
    /// Matches Flutter CreateProduct mutation and Variables$Mutation$CreateProduct.
    func createProduct(
        name: String,
        description: String,
        price: Double,
        imageUrl: [(url: String, thumbnail: String)],
        categoryId: Int,
        condition: String? = nil,
        parcelSize: String? = nil,
        discount: Double? = nil,
        color: [String]? = nil,
        brandId: Int? = nil,
        customBrand: String? = nil,
        materialIds: [Int]? = nil,
        style: String? = nil,
        styles: [String]? = nil,
        sizeId: Int? = nil,
        status: String = "ACTIVE"
    ) async throws -> Int {
        let mutation = """
        mutation CreateProduct(
          $category: Int!
          $condition: ConditionEnum
          $description: String!
          $imageUrl: [ImagesInputType]!
          $price: Float!
          $size: Int
          $name: String!
          $parcelSize: ParcelSizeEnum
          $discount: Float
          $color: [String]
          $brand: Int
          $materials: [Int]
          $style: StyleEnum
          $styles: [StyleEnum]
          $customBrand: String
          $isFeatured: Boolean
          $status: ProductStatusEnum
        ) {
          createProduct(
            category: $category
            condition: $condition
            description: $description
            imagesUrl: $imageUrl
            price: $price
            size: $size
            name: $name
            parcelSize: $parcelSize
            discount: $discount
            color: $color
            brand: $brand
            materials: $materials
            style: $style
            styles: $styles
            customBrand: $customBrand
            isFeatured: $isFeatured
            status: $status
          ) {
            success
            message
            product {
              id
            }
          }
        }
        """
        var variables: [String: Any] = [
            "category": categoryId,
            "description": description,
            "imageUrl": imageUrl.map { ["url": $0.url, "thumbnail": $0.thumbnail] },
            "price": price,
            "name": name,
            "status": status
        ]
        if let c = condition, !c.isEmpty { variables["condition"] = c }
        if let ps = parcelSize, !ps.isEmpty { variables["parcelSize"] = ps }
        // Backend expects discount as percentage (0–100). UI sends discounted (sale) price in pounds; convert to %.
        let discountPercent: Double
        if let salePrice = discount, salePrice > 0, salePrice < price {
            discountPercent = ((price - salePrice) / price) * 100
        } else {
            discountPercent = 0
        }
        variables["discount"] = max(0, min(100, discountPercent))
        if let col = color, !col.isEmpty { variables["color"] = col }
        if let bid = brandId { variables["brand"] = bid }
        if let cb = customBrand, !cb.isEmpty { variables["customBrand"] = cb }
        if let mat = materialIds, !mat.isEmpty { variables["materials"] = mat }
        if let s = style, !s.isEmpty { variables["style"] = s }
        if let st = styles, !st.isEmpty { variables["styles"] = st }
        if let sid = sizeId { variables["size"] = sid }

        struct CreateProductResponse: Decodable {
            let createProduct: CreateProductPayload?
        }
        struct CreateProductPayload: Decodable {
            let success: Bool?
            let message: String?
            let product: ProductIdPayload?
        }
        struct ProductIdPayload: Decodable {
            let id: AnyCodable?
        }

        let response: CreateProductResponse = try await client.execute(
            query: mutation,
            variables: variables,
            operationName: "CreateProduct",
            responseType: CreateProductResponse.self
        )
        guard let payload = response.createProduct, payload.success == true else {
            let msg = response.createProduct?.message ?? "Create product failed"
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard let product = payload.product else {
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No product id returned"])
        }
        let idVal: Int
        if let v = product.id?.value as? Int {
            idVal = v
        } else if let s = product.id?.value as? String, let v = Int(s) {
            idVal = v
        } else {
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No product id returned"])
        }
        return idVal
    }

    /// Update an existing listing (seller only). Omit `imagePairs` to keep current photos; pass full list + `UPDATE_INDEX` to replace images after upload.
    func updateProduct(
        productId: Int,
        name: String,
        description: String,
        price: Double,
        categoryId: Int,
        condition: String? = nil,
        parcelSize: String? = nil,
        discountSalePrice: Double? = nil,
        color: [String]? = nil,
        brandId: Int? = nil,
        customBrand: String? = nil,
        materialIds: [Int]? = nil,
        style: String? = nil,
        styles: [String]? = nil,
        sizeId: Int? = nil,
        imagePairs: [(url: String, thumbnail: String)]? = nil,
        imageAction: String? = nil
    ) async throws {
        let mutation = """
        mutation UpdateProduct(
          $productId: Int!
          $category: Int
          $condition: ConditionEnum
          $description: String
          $imagesUrl: ImageUpdateInputType
          $price: Float
          $size: Int
          $name: String
          $parcelSize: ParcelSizeEnum
          $discountPrice: Float
          $color: [String]
          $brand: Int
          $materials: [Int]
          $style: StyleEnum
          $styles: [StyleEnum]
          $customBrand: String
        ) {
          updateProduct(
            productId: $productId
            category: $category
            condition: $condition
            description: $description
            imagesUrl: $imagesUrl
            price: $price
            size: $size
            name: $name
            parcelSize: $parcelSize
            discountPrice: $discountPrice
            color: $color
            brand: $brand
            materials: $materials
            style: $style
            styles: $styles
            customBrand: $customBrand
          ) {
            success
            message
            product { id }
          }
        }
        """
        var variables: [String: Any] = [
            "productId": productId,
            "name": name,
            "description": description,
            "price": price,
            "category": categoryId
        ]
        if let c = condition, !c.isEmpty { variables["condition"] = c }
        if let ps = parcelSize, !ps.isEmpty { variables["parcelSize"] = ps }
        let discountPercent: Double
        if let sale = discountSalePrice, sale > 0, sale < price {
            discountPercent = ((price - sale) / price) * 100
        } else {
            discountPercent = 0
        }
        variables["discountPrice"] = max(0, min(100, discountPercent))
        if let col = color, !col.isEmpty { variables["color"] = col }
        if let bid = brandId { variables["brand"] = bid }
        if let cb = customBrand, !cb.isEmpty { variables["customBrand"] = cb }
        if let mat = materialIds, !mat.isEmpty { variables["materials"] = mat }
        if let s = style, !s.isEmpty { variables["style"] = s }
        if let st = styles, !st.isEmpty { variables["styles"] = st }
        if let sid = sizeId { variables["size"] = sid }
        if let pairs = imagePairs, !pairs.isEmpty, let action = imageAction, !action.isEmpty {
            variables["imagesUrl"] = [
                "images": pairs.map { ["url": $0.url, "thumbnail": $0.thumbnail] },
                "action": action
            ]
        }
        struct UpdateProductResponse: Decodable {
            let updateProduct: UpdateProductPayload?
        }
        struct UpdateProductPayload: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: UpdateProductResponse = try await client.execute(
            query: mutation,
            variables: variables,
            operationName: "UpdateProduct",
            responseType: UpdateProductResponse.self
        )
        guard response.updateProduct?.success == true else {
            let msg = response.updateProduct?.message ?? "Update failed"
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Delete a product (own listing). Matches Flutter/backend deleteProduct if available.
    func deleteProduct(productId: Int) async throws {
        let mutation = """
        mutation DeleteProduct($productId: Int!) {
          deleteProduct(productId: $productId) {
            success
            message
          }
        }
        """
        struct Payload: Decodable {
            let deleteProduct: DeleteProductPayload?
        }
        struct DeleteProductPayload: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(query: mutation, variables: ["productId": productId], responseType: Payload.self)
        guard response.deleteProduct?.success == true else {
            let msg = response.deleteProduct?.message ?? "Failed to delete listing"
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Report a product. Matches Flutter reportProduct(reason, productId, content?).
    func reportProduct(productId: String, reason: String, content: String? = nil, imagesUrl: [String] = []) async throws -> SubmittedReportRef? {
        let mutation = """
        mutation ReportProduct($reason: String!, $productId: ID!, $content: String, $imagesUrl: [String]) {
          reportProduct(reason: $reason, productId: $productId, content: $content, imagesUrl: $imagesUrl) {
            success
            message
            reportId
            publicId
          }
        }
        """
        var variables: [String: Any] = ["reason": reason, "productId": productId, "imagesUrl": imagesUrl]
        if let c = content, !c.isEmpty { variables["content"] = c }
        struct Payload: Decodable { let reportProduct: ReportProductResult? }
        struct ReportProductResult: Decodable {
            let success: Bool?
            let message: String?
            let reportId: Int?
            let publicId: String?
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        return response.reportProduct.map {
            SubmittedReportRef(
                reportId: $0.reportId,
                publicId: $0.publicId,
                supportConversationId: nil
            )
        }
    }

    /// Mark product as sold. Matches Flutter/backend updateProduct status if available.
    func updateProductStatus(productId: Int, status: String) async throws {
        let mutation = """
        mutation UpdateProductStatus($productId: Int!, $status: ProductStatusEnum!) {
          updateProductStatus(productId: $productId, status: $status) {
            success
            message
          }
        }
        """
        struct Payload: Decodable {
            let updateProductStatus: UpdateStatusPayload?
        }
        struct UpdateStatusPayload: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(query: mutation, variables: ["productId": productId, "status": status], responseType: Payload.self)
        guard response.updateProductStatus?.success == true else {
            let msg = response.updateProductStatus?.message ?? "Failed to update listing"
            throw NSError(domain: "ProductService", code: -1, userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Fetch sizes for a category path (e.g. "Women > Clothing"). Backend uses first two path segments. Matches Flutter fetchSizes(fullPath).
    func fetchSizes(path: String) async throws -> [APISize] {
        let query = """
        query Sizes($path: String!) {
          sizes(path: $path) {
            id
            name
          }
        }
        """
        struct SizesResponseInner: Decodable {
            let sizes: [APISizeRaw]?
        }
        struct APISizeRaw: Decodable {
            let id: AnyCodable?
            let name: String?
        }
        let response: SizesResponseInner = try await client.execute(
            query: query,
            variables: ["path": path],
            operationName: "Sizes",
            responseType: SizesResponseInner.self
        )
        let rawList = response.sizes ?? []
        return rawList.compactMap { r -> APISize? in
            guard let name = r.name else { return nil }
            let id: Int? = (r.id?.value as? Int) ?? (r.id?.value as? String).flatMap { Int($0) }
            return APISize(id: id, name: name)
        }
    }

    func getLikedProducts(pageNumber: Int = 1, pageCount: Int = 50) async throws -> (items: [Item], totalNumber: Int) {
        let query = """
        query LikedProducts($pageCount: Int, $pageNumber: Int) {
          likedProducts(pageCount: $pageCount, pageNumber: $pageNumber) {
            product {
              id
              listingCode
              name
              description
              price
              discountPrice
              imagesUrl
              condition
              createdAt
              size { id name }
              brand { id name }
              customBrand
              likes
              views
              userLiked
            seller { id username displayName profilePictureUrl isVacationMode meta }
            category { id name }
            color
            }
          }
          likedProductsTotalNumber
        }
        """
        struct LikedProductsResponse: Decodable {
            let likedProducts: [LikedProductRow]?
            let likedProductsTotalNumber: Int?
        }
        struct LikedProductRow: Decodable {
            let product: ProductData?
        }
        let response: LikedProductsResponse = try await client.execute(
            query: query,
            variables: ["pageCount": pageCount, "pageNumber": pageNumber],
            responseType: LikedProductsResponse.self
        )
        let products = (response.likedProducts ?? []).compactMap { $0.product }
        let items = products.compactMap { mapProductToItem(product: $0) }
        let total = response.likedProductsTotalNumber ?? 0
        return (items, total)
    }

    /// Toggle like on a product. Matches Flutter likeProduct mutation.
    func likeProduct(productId: Int) async throws -> Bool {
        let mutation = """
        mutation LikeProduct($productId: Int!) {
          likeProduct(productId: $productId) {
            success
          }
        }
        """
        struct Payload: Decodable { let likeProduct: LikeProductPayload? }
        struct LikeProductPayload: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: ["productId": productId], responseType: Payload.self)
        return response.likeProduct?.success ?? false
    }

    /// Create an offer (buyer sends price + product ids). Matches Flutter createOffer(offerPrice, productIds, message).
    /// Returns (success, conversation) so caller can navigate to chat with offer card. productIds must be [Int].
    func createOffer(offerPrice: Double, productIds: [Int], message: String? = nil) async throws -> (success: Bool, conversation: Conversation?) {
        let mutation = """
        mutation CreateOffer($offerPrice: Float!, $productIds: [Int]!, $message: String) {
          createOffer(offerPrice: $offerPrice, productIds: $productIds, message: $message) {
            success
            message
            data {
              conversationId
              offer {
                id
                status
                offerPrice
                buyer { username profilePictureUrl }
                products { id name seller { username profilePictureUrl } }
              }
            }
          }
        }
        """
        struct Payload: Decodable {
            let createOffer: CreateOfferPayload?
        }
        struct CreateOfferPayload: Decodable {
            let success: Bool?
            let message: String?
            let data: CreateOfferData?
            /// Backend may put conversationId/offer at top level instead of under data.
            let conversationId: AnyCodable?
            let offer: [CreateOfferData.OfferElement]?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                success = try c.decodeIfPresent(Bool.self, forKey: .success)
                message = try c.decodeIfPresent(String.self, forKey: .message)
                data = try c.decodeIfPresent(CreateOfferData.self, forKey: .data)
                conversationId = try c.decodeIfPresent(AnyCodable.self, forKey: .conversationId)
                if let arr = try? c.decode([CreateOfferData.OfferElement].self, forKey: .offer) {
                    offer = arr
                } else if let single = try? c.decode(CreateOfferData.OfferElement.self, forKey: .offer) {
                    offer = [single]
                } else {
                    offer = nil
                }
            }
            private enum CodingKeys: String, CodingKey { case success, message, data, conversationId, offer }
            /// Effective data: from nested data or from top-level conversationId/offer.
            var effectiveData: CreateOfferData? {
                if let d = data { return d }
                if conversationId != nil || (offer != nil && !(offer ?? []).isEmpty) {
                    return CreateOfferData(conversationId: conversationId, offer: offer)
                }
                return nil
            }
        }
        struct CreateOfferData: Decodable {
            let conversationId: AnyCodable?
            let offer: [OfferElement]?
            init(conversationId: AnyCodable?, offer: [OfferElement]?) {
                self.conversationId = conversationId
                self.offer = offer
            }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                conversationId = try c.decodeIfPresent(AnyCodable.self, forKey: .conversationId)
                if let arr = try? c.decode([OfferElement].self, forKey: .offer) {
                    offer = arr
                } else if let single = try? c.decode(OfferElement.self, forKey: .offer) {
                    offer = [single]
                } else {
                    offer = nil
                }
            }
            private enum CodingKeys: String, CodingKey { case conversationId, offer }
            struct OfferElement: Decodable {
                let id: AnyCodable?
                let status: String?
                let offerPrice: CreateOfferDoubleOrDecimal?
                let buyer: Buyer?
                let products: [ProductEl]?
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    id = try? c.decode(AnyCodable.self, forKey: .id)
                    status = try? c.decode(String.self, forKey: .status)
                    offerPrice = try? c.decode(CreateOfferDoubleOrDecimal.self, forKey: .offerPrice)
                    buyer = try? c.decode(Buyer.self, forKey: .buyer)
                    products = try? c.decode([ProductEl].self, forKey: .products)
                }
                private enum CodingKeys: String, CodingKey { case id, status, offerPrice, buyer, products }
                struct Buyer: Decodable {
                    let username: String?
                    let profilePictureUrl: String?
                }
                struct ProductEl: Decodable {
                    let id: AnyCodable?
                    let name: String?
                    let seller: Buyer?
                }
            }
        }
        /// Accepts Double, Decimal, or String for offerPrice (backend may return any).
        enum CreateOfferDoubleOrDecimal: Decodable {
            case double(Double)
            case decimal(Decimal)
            case string(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let d = try? c.decode(Double.self) { self = .double(d); return }
                if let dec = try? c.decode(Decimal.self) { self = .decimal(dec); return }
                if let s = try? c.decode(String.self) { self = .string(s); return }
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Double, Decimal, or String for offerPrice")
            }
            var value: Double {
                switch self {
                case .double(let d): return d
                case .decimal(let d): return NSDecimalNumber(decimal: d).doubleValue
                case .string(let s): return Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }
        }
        var variables: [String: Any] = ["offerPrice": offerPrice, "productIds": productIds]
        if let m = message, !m.isEmpty { variables["message"] = m }
        let response: Payload
        do {
            response = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        } catch let err as GraphQLError {
            // Backend may return a shape we don't expect; don't show decoding error to user
            if case .decodingError = err { return (true, nil) }
            throw err
        } catch {
            throw error
        }
        guard let offer = response.createOffer else { throw NSError(domain: "CreateOffer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]) }
        if offer.success != true {
            throw NSError(domain: "CreateOffer", code: -1, userInfo: [NSLocalizedDescriptionKey: offer.message ?? "Failed to create offer"])
        }
        guard let data = offer.effectiveData else {
            return (true, nil)
        }
        let convIdStr: String = {
            guard let any = data.conversationId?.value else { return "" }
            if let i = any as? Int { return String(i) }
            if let s = any as? String { return s }
            return String(describing: any)
        }()
        guard !convIdStr.isEmpty, data.offer?.first != nil else {
            return (true, nil)
        }
        let conversation: Conversation? = data.offer?.first.map { el in
            let idStr = (el.id?.value as? String) ?? (el.id?.value as? Int).map { String($0) } ?? ""
            let price = el.offerPrice?.value ?? 0
            let buyer = el.buyer.map { OfferInfo.OfferUser(username: $0.username, profilePictureUrl: $0.profilePictureUrl) }
            let products = el.products?.map { p in
                let pid = (p.id?.value as? Int).map { String($0) } ?? (p.id?.value as? String) ?? ""
                return OfferInfo.OfferProduct(
                    id: pid,
                    name: p.name,
                    seller: p.seller.map { OfferInfo.OfferUser(username: $0.username, profilePictureUrl: $0.profilePictureUrl) }
                )
            }
            let fb = el.buyer?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let financialBuyer = fb.isEmpty ? nil : fb
            let offerInfo = OfferInfo(id: idStr, status: el.status, offerPrice: price, buyer: buyer, products: products, sentByCurrentUser: true, financialBuyerUsername: financialBuyer)
            let seller = el.products?.first?.seller
            let recipient = User(
                id: UUID(),
                username: seller?.username ?? "",
                displayName: seller?.username ?? "",
                avatarURL: seller?.profilePictureUrl
            )
            return Conversation(
                id: convIdStr,
                recipient: recipient,
                lastMessage: nil,
                lastMessageTime: nil,
                unreadCount: 0,
                offer: offerInfo
            )
        }
        return (true, conversation)
    }

    /// Create an order (buy now or from accepted offer). Matches Flutter createOrder. Pass either productId (single) or productIds (multi); deliveryDetails required.
    /// When `productIds` span multiple sellers, pass `sellerShippingFees` (backend seller user id + fee) so the API can create one order per seller.
    func createOrder(productId: Int? = nil, productIds: [Int]? = nil, buyerProtection: Bool? = nil, shippingFee: Float? = nil, sellerShippingFees: [(sellerId: Int, shippingFee: Float)]? = nil, deliveryDetails: CreateOrderDeliveryDetails) async throws -> CreateOrderResult {
        let mutation = """
        mutation CreateOrder($productId: Int, $productIds: [Int], $buyerProtection: Boolean, $shippingFee: Float, $sellerShippingFees: [SellerShippingFeeInput!], $deliveryDetails: DeliveryDetailsInputType!) {
          createOrder(productId: $productId, productIds: $productIds, buyerProtection: $buyerProtection, shippingFee: $shippingFee, sellerShippingFees: $sellerShippingFees, deliveryDetails: $deliveryDetails) {
            success
            order { id priceTotal status }
          }
        }
        """
        struct Payload: Decodable {
            let createOrder: CreateOrderPayload?
        }
        struct CreateOrderPayload: Decodable {
            let success: Bool?
            let order: CreateOrderOrder?
        }
        struct CreateOrderOrder: Decodable {
            let id: AnyCodable?
            let priceTotal: String?
            let status: String?
        }
        var variables: [String: Any] = [
            "deliveryDetails": deliveryDetails.toGraphQLVariables()
        ]
        if let pid = productId { variables["productId"] = pid }
        if let pids = productIds { variables["productIds"] = pids }
        if let bp = buyerProtection { variables["buyerProtection"] = bp }
        if let fee = shippingFee { variables["shippingFee"] = fee }
        if let rows = sellerShippingFees, !rows.isEmpty {
            variables["sellerShippingFees"] = rows.map { ["sellerId": $0.sellerId, "shippingFee": $0.shippingFee] }
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        guard let create = response.createOrder else { throw NSError(domain: "CreateOrder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown error"]) }
        if create.success != true {
            throw NSError(domain: "CreateOrder", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create order"])
        }
        // Support numeric (legacy) or alphanumeric with PR prefix (e.g. PR23DG2DF3)
        let idVal = create.order?.id?.value
        let orderIdStr = (idVal as? String) ?? (idVal as? Int).map { String($0) } ?? ""
        return CreateOrderResult(success: true, orderId: orderIdStr, orderStatus: create.order?.status)
    }

    /// Respond to an offer (accept, reject, or counter). Matches Flutter respondToOffer. action: ACCEPT, REJECT, COUNTER; offerPrice required for COUNTER.
    func respondToOffer(action: String, offerId: Int, offerPrice: Double? = nil) async throws {
        let mutation = """
        mutation RespondToOffer($action: OfferActionEnum!, $offerId: Int!, $offerPrice: Float) {
          respondToOffer(action: $action, offerId: $offerId, offerPrice: $offerPrice) {
            success
            message
          }
        }
        """
        struct Payload: Decodable { let respondToOffer: RespondToOfferPayload? }
        struct RespondToOfferPayload: Decodable { let success: Bool?; let message: String? }
        var variables: [String: Any] = ["action": action, "offerId": offerId]
        if let price = offerPrice { variables["offerPrice"] = price }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        if response.respondToOffer?.success != true {
            throw NSError(domain: "RespondToOffer", code: -1, userInfo: [NSLocalizedDescriptionKey: response.respondToOffer?.message ?? "Failed to respond to offer"])
        }
    }

    // Map category filter names to GraphQL enum values
    private func mapCategoryToEnum(_ category: String) -> String? {
        switch category {
        case "Women":
            return "WOMEN"
        case "Men":
            return "MEN"
        case "Toddlers":
            return "TODDLERS"
        case "Boys":
            return "BOYS"
        case "Girls":
            return "GIRLS"
        default:
            return nil
        }
    }
}

struct AllProductsResponse: Decodable {
    let allProducts: [ProductData]?
    let allProductsTotalNumber: Int?
}

struct ProductData: Decodable {
    let id: AnyCodable?
    let listingCode: String?
    let name: String?
    let description: String?
    let price: Double?
    let discountPrice: String?
    let imagesUrl: [String]?
    let condition: String?
    let createdAt: String?  // ISO8601 from GraphQL
    let size: SizeData?
    let brand: BrandData?
    let customBrand: String?
    let color: [String]?
    let likes: Int?
    let views: Int?
    let userLiked: Bool?
    let seller: SellerData?
    let category: CategoryData?
    let status: String?
}

struct SizeData: Decodable {
    let id: AnyCodable?
    let name: String?
}

/// Size option from sizes(path) query for sell form.
struct APISize {
    let id: Int?
    let name: String
}

struct BrandData: Decodable {
    let id: AnyCodable?
    let name: String?
}

struct SellerData: Decodable {
    let id: AnyCodable?
    let username: String?
    let displayName: String?
    let profilePictureUrl: String?
    let isVacationMode: Bool?
    /// Backend may send meta as object or JSON string; use SafeMetaDecode so decoding never fails.
    let meta: SafeMetaDecode?
}

struct CategoryData: Decodable {
    let id: AnyCodable?
    let name: String?
}

/// One entry from userProductGrouping (group by category/brand). Matches Flutter CategoryGroupType.
struct CategoryGroup {
    let id: Int
    let name: String
    let count: Int
}

/// Input for createOrder mutation. Matches DeliveryDetailsInputType + DeliveryAddressInputType.
struct CreateOrderDeliveryDetails {
    let address: String
    let city: String
    let state: String
    let country: String
    let postalCode: String
    let phoneNumber: String
    /// DeliveryProviderEnum: DPD, EVRI, UDEL, ROYAL_MAIL
    let deliveryProvider: String
    /// DeliveryTypeEnum: HOME_DELIVERY, LOCAL_PICKUP
    let deliveryType: String
    /// Human-readable shipping option selected at checkout (e.g. "Royal Mail First Class (Next day)")
    let shippingOptionName: String?

    func toGraphQLVariables() -> [String: Any] {
        [
            "deliveryAddress": [
                "address": address,
                "city": city,
                "state": state,
                "country": country,
                "postalCode": postalCode,
                "phoneNumber": phoneNumber
            ],
            "deliveryProvider": deliveryProvider,
            "deliveryType": deliveryType,
            "shippingOptionName": shippingOptionName ?? ""
        ]
    }

    /// Build from User.ShippingAddress (and phone) for checkout.
    static func from(shippingAddress: ShippingAddress, phoneNumber: String, deliveryProvider: String = "EVRI", deliveryType: String = "HOME_DELIVERY", shippingOptionName: String? = nil) -> CreateOrderDeliveryDetails {
        CreateOrderDeliveryDetails(
            address: shippingAddress.address,
            city: shippingAddress.city,
            state: shippingAddress.state ?? "",
            country: shippingAddress.country,
            postalCode: shippingAddress.postcode,
            phoneNumber: phoneNumber,
            deliveryProvider: deliveryProvider,
            deliveryType: deliveryType,
            shippingOptionName: shippingOptionName
        )
    }
}

/// Result of createOrder mutation.
struct CreateOrderResult {
    let success: Bool
    let orderId: String
    let orderStatus: String?
}

extension ProductService {
    /// Fetch a single product by numeric id (for deep links / notifications).
    func getProduct(id: Int) async throws -> Item? {
        try await getProduct(publicSlug: String(id))
    }

    /// Resolve by backend id (all-digit slug) or public `listingCode` (web `/item/...`).
    func getProduct(publicSlug: String) async throws -> Item? {
        let trimmed = publicSlug.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let query = """
        query ProductDetail($id: Int, $listingCode: String) {
          product(id: $id, listingCode: $listingCode) {
            id
            listingCode
            name
            description
            price
            discountPrice
            imagesUrl
            condition
            createdAt
            size { id name }
            brand { id name }
            customBrand
            likes
            views
            userLiked
            seller { id username displayName profilePictureUrl isVacationMode meta }
            category { id name }
            color
            status
          }
        }
        """
        struct ProductDetailResponse: Decodable {
            let product: ProductData?
        }
        var variables: [String: Any] = [:]
        if trimmed.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }), let pid = Int(trimmed) {
            variables["id"] = pid
        } else {
            variables["listingCode"] = trimmed
        }
        let response: ProductDetailResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: ProductDetailResponse.self
        )
        guard let product = response.product else { return nil }
        return mapProductToItem(product: product)
    }

    func getRecentlyViewedProducts() async throws -> [Item] {
        let query = """
        query RecentlyViewedProducts {
          recentlyViewedProducts {
            id
            listingCode
            name
            description
            price
            discountPrice
            imagesUrl
            condition
            createdAt
            size {
              id
              name
            }
            brand {
              id
              name
            }
            customBrand
            likes
            views
            userLiked
            seller {
              id
              username
              displayName
              profilePictureUrl
              isVacationMode
              meta
            }
            category {
              id
              name
            }
            color
            status
          }
        }
        """
        
        struct RecentlyViewedProductsResponse: Decodable {
            let recentlyViewedProducts: [ProductData]?
        }
        
        let response: RecentlyViewedProductsResponse = try await client.execute(
            query: query,
            variables: nil,
            responseType: RecentlyViewedProductsResponse.self
        )
        
        guard let products = response.recentlyViewedProducts else {
            return []
        }
        
        return products.compactMap { product in
            // Extract product id
            let idString: String
            if let productId = product.id {
                if let intValue = productId.value as? Int {
                    idString = String(intValue)
                } else if let stringValue = productId.value as? String {
                    idString = stringValue
                } else {
                    idString = String(describing: productId.value)
                }
            } else {
                idString = UUID().uuidString
            }
            
            // Extract seller id (string for UUID, int for backend userId / multibuy)
            let sellerIdString: String
            let sellerUserIdInt: Int?
            if let sellerId = product.seller?.id {
                if let intValue = sellerId.value as? Int {
                    sellerIdString = String(intValue)
                    sellerUserIdInt = intValue
                } else if let stringValue = sellerId.value as? String {
                    sellerIdString = stringValue
                    sellerUserIdInt = Int(stringValue)
                } else {
                    sellerIdString = String(describing: sellerId.value)
                    sellerUserIdInt = nil
                }
            } else {
                sellerIdString = ""
                sellerUserIdInt = nil
            }
            
            // Parse discountPrice (it's a percentage string, e.g., "20" for 20% off)
            let originalPrice = product.price ?? 0.0
            let discountPercentage: Double? = {
                guard let discountPriceStr = product.discountPrice,
                      let discount = Double(discountPriceStr),
                      discount > 0 else {
                    return nil
                }
                return discount
            }()
            
            // Calculate final price: if discount exists, apply it; otherwise use original price
            let finalPrice: Double
            let itemOriginalPrice: Double?
            if let discount = discountPercentage {
                // Calculate discounted price: originalPrice - (originalPrice * discount / 100)
                finalPrice = originalPrice - (originalPrice * discount / 100)
                itemOriginalPrice = originalPrice
            } else {
                finalPrice = originalPrice
                itemOriginalPrice = nil
            }
            
            // Extract image URLs from imagesUrl array (which contains JSON strings)
            let imageURLs = extractImageURLs(from: product.imagesUrl)
            let listDisplayURL = ProductListImageURL.preferredString(fromImagesUrlArray: product.imagesUrl) ?? imageURLs.first

            // Get brand name (use customBrand as fallback)
            let brandName = product.brand?.name ?? product.customBrand
            
            // Get size
            let sizeName = product.size?.name ?? "One Size"
            
            let listingCode: String? = {
                guard let lc = product.listingCode?.trimmingCharacters(in: .whitespacesAndNewlines), !lc.isEmpty else { return nil }
                return lc
            }()
            return Item(
                id: Item.id(fromProductId: idString),
                productId: idString,
                listingCode: listingCode,
                title: product.name ?? "",
                description: product.description ?? "",
                price: finalPrice,
                originalPrice: itemOriginalPrice,
                imageURLs: imageURLs,
                listDisplayImageURL: listDisplayURL,
                category: Category.fromName(product.category?.name ?? ""),
                categoryName: product.category?.name, // Store actual category name from API (subcategory)
                seller: User(
                    id: UUID(uuidString: sellerIdString) ?? UUID(),
                    userId: sellerUserIdInt,
                    username: product.seller?.username ?? "",
                    displayName: product.seller?.displayName ?? "",
                    avatarURL: product.seller?.profilePictureUrl,
                    isVacationMode: product.seller?.isVacationMode ?? false,
                    postageOptions: SellerPostageOptions.from(decoded: product.seller?.meta?.value?.postage)
                ),
                condition: product.condition ?? "UNKNOWN",
                size: sizeName,
                brand: brandName,
                colors: product.color ?? [],
                likeCount: product.likes ?? 0,
                views: product.views ?? 0,
                createdAt: Self.parseCreatedAt(product.createdAt) ?? Date(),
                isLiked: product.userLiked ?? false,
                status: product.status ?? "ACTIVE",
                sellCategoryBackendId: Self.graphQLStringId(product.category?.id),
                sellSizeBackendId: Self.graphQLIntId(product.size?.id)
            )
        }
    }

    /// Record product view for recently viewed. Call when user opens product detail. Matches backend mutation used by Flutter. Ignores errors so missing/different schema does not break the app.
    func addToRecentlyViewed(productId: Int) async {
        let mutation = """
        mutation AddToRecentlyViewed($productId: Int!) {
          addToRecentlyViewed(productId: $productId) {
            success
          }
        }
        """
        struct Payload: Decodable { let addToRecentlyViewed: AddToRecentlyViewedPayload? }
        struct AddToRecentlyViewedPayload: Decodable { let success: Bool? }
        do {
            _ = try await client.execute(query: mutation, variables: ["productId": productId], responseType: Payload.self)
        } catch {
            // Backend may use different mutation name or record view via product(id:) query; ignore so UI is unaffected
        }
    }

    func getSimilarProducts(productId: String, categoryId: Int? = nil, pageNumber: Int = 1, pageCount: Int = 20) async throws -> [Item] {
        let query = """
        query SimilarProducts($productId: Int, $categoryId: Int, $pageNumber: Int, $pageCount: Int) {
          similarProducts(productId: $productId, categoryId: $categoryId, pageNumber: $pageNumber, pageCount: $pageCount) {
            id
            listingCode
            name
            description
            price
            discountPrice
            imagesUrl
            condition
            createdAt
            size {
              id
              name
            }
            brand {
              id
              name
            }
            customBrand
            likes
            views
            userLiked
            seller {
              id
              username
              displayName
              profilePictureUrl
              isVacationMode
              meta
            }
            category {
              id
              name
            }
            color
            status
          }
        }
        """
        
        var variables: [String: Any] = [
            "pageNumber": pageNumber,
            "pageCount": pageCount
        ]
        
        if let productIdInt = Int(productId) {
            variables["productId"] = productIdInt
        }
        
        if let categoryId = categoryId {
            variables["categoryId"] = categoryId
        }
        
        struct SimilarProductsResponse: Decodable {
            let similarProducts: [ProductData]?
        }
        
        let response: SimilarProductsResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: SimilarProductsResponse.self
        )
        
        guard let products = response.similarProducts else {
            return []
        }
        
        return products.compactMap { product in
            return mapProductToItem(product: product)
        }
    }
    
    /// Result of toggling a like: isLiked state and optional likeCount (nil when server doesn't return it, e.g. when using likeProduct fallback).
    struct ToggleLikeResult {
        let isLiked: Bool
        let likeCount: Int?
    }

    func toggleLike(productId: String, isLiked: Bool) async throws -> ToggleLikeResult {
        guard let productIdInt = Int(productId) else {
            throw NSError(domain: "ProductService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid product ID"])
        }

        // Prefer toggleLikeProduct (returns isLiked + likeCount). Fall back to likeProduct (toggle) if backend only has that.
        do {
            let mutation = """
            mutation ToggleLike($productId: Int!, $isLiked: Boolean!) {
              toggleLikeProduct(productId: $productId, isLiked: $isLiked) {
                isLiked
                likeCount
              }
            }
            """
            struct ToggleLikeResponse: Decodable {
                let toggleLikeProduct: ToggleLikeData?
            }
            struct ToggleLikeData: Decodable {
                let isLiked: Bool?
                let likeCount: Int?
            }
            let variables: [String: Any] = ["productId": productIdInt, "isLiked": isLiked]
            let response: ToggleLikeResponse = try await client.execute(
                query: mutation,
                variables: variables,
                responseType: ToggleLikeResponse.self
            )
            guard let data = response.toggleLikeProduct else {
                throw NSError(domain: "ProductService", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to toggle like"])
            }
            return ToggleLikeResult(
                isLiked: data.isLiked ?? isLiked,
                likeCount: data.likeCount
            )
        } catch {
            // Fallback: backend may only expose likeProduct (often implemented as toggle: like/unlike)
            let success = try await likeProduct(productId: productIdInt)
            if !success { throw error }
            return ToggleLikeResult(isLiked: isLiked, likeCount: nil)
        }
    }

    private static func graphQLStringId(_ codable: AnyCodable?) -> String? {
        guard let v = codable?.value else { return nil }
        if let i = v as? Int { return String(i) }
        if let s = v as? String, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return s }
        return nil
    }

    private static func graphQLIntId(_ codable: AnyCodable?) -> Int? {
        guard let v = codable?.value else { return nil }
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
    
    private func mapProductToItem(product: ProductData) -> Item? {
        // Extract product id
        let idString: String
        if let productId = product.id {
            if let intValue = productId.value as? Int {
                idString = String(intValue)
            } else if let stringValue = productId.value as? String {
                idString = stringValue
            } else {
                idString = String(describing: productId.value)
            }
        } else {
            idString = UUID().uuidString
        }
        
        // Extract seller id (string for UUID, int for backend userId / multibuy)
        let sellerIdString: String
        let sellerUserIdInt: Int?
        if let sellerId = product.seller?.id {
            if let intValue = sellerId.value as? Int {
                sellerIdString = String(intValue)
                sellerUserIdInt = intValue
            } else if let stringValue = sellerId.value as? String {
                sellerIdString = stringValue
                sellerUserIdInt = Int(stringValue)
            } else {
                sellerIdString = String(describing: sellerId.value)
                sellerUserIdInt = nil
            }
        } else {
            sellerIdString = ""
            sellerUserIdInt = nil
        }
        
        // Parse discountPrice (it's a percentage string, e.g., "20" for 20% off)
        let originalPrice = product.price ?? 0.0
        let discountPercentage: Double? = {
            guard let discountPriceStr = product.discountPrice,
                  let discount = Double(discountPriceStr),
                  discount > 0 else {
                return nil
            }
            return discount
        }()
        
        // Calculate final price: if discount exists, apply it; otherwise use original price
        let finalPrice: Double
        let itemOriginalPrice: Double?
        if let discount = discountPercentage {
            // Calculate discounted price: originalPrice - (originalPrice * discount / 100)
            finalPrice = originalPrice - (originalPrice * discount / 100)
            itemOriginalPrice = originalPrice
        } else {
            finalPrice = originalPrice
            itemOriginalPrice = nil
        }

        // Extract image URLs from imagesUrl array (which contains JSON strings)
        let imageURLs = extractImageURLs(from: product.imagesUrl)
        let listDisplayURL = ProductListImageURL.preferredString(fromImagesUrlArray: product.imagesUrl) ?? imageURLs.first

        // Get brand name (use customBrand as fallback)
        let brandName = product.brand?.name ?? product.customBrand

        // Get size
        let sizeName = product.size?.name ?? "One Size"

        let listingCode: String? = {
            guard let lc = product.listingCode?.trimmingCharacters(in: .whitespacesAndNewlines), !lc.isEmpty else { return nil }
            return lc
        }()

        return Item(
            id: Item.id(fromProductId: idString),
            productId: idString,
            listingCode: listingCode,
            title: product.name ?? "",
            description: product.description ?? "",
            price: finalPrice,
            originalPrice: itemOriginalPrice,
            imageURLs: imageURLs,
            listDisplayImageURL: listDisplayURL,
            category: Category.fromName(product.category?.name ?? ""),
            categoryName: product.category?.name,
            seller: User(
                id: sellerUserIdInt.map { User.stableIdForSeller(backendUserId: $0) } ?? (UUID(uuidString: sellerIdString) ?? UUID()),
                userId: sellerUserIdInt,
                username: product.seller?.username ?? "",
                displayName: product.seller?.displayName ?? "",
                avatarURL: product.seller?.profilePictureUrl,
                isVacationMode: product.seller?.isVacationMode ?? false,
                postageOptions: SellerPostageOptions.from(decoded: product.seller?.meta?.value?.postage)
            ),
            condition: product.condition ?? "UNKNOWN",
            size: sizeName,
            brand: brandName,
            colors: product.color ?? [],
            likeCount: product.likes ?? 0,
            views: product.views ?? 0,
            createdAt: Self.parseCreatedAt(product.createdAt) ?? Date(),
            isLiked: product.userLiked ?? false,
            status: product.status ?? "ACTIVE",
            sellCategoryBackendId: Self.graphQLStringId(product.category?.id),
            sellSizeBackendId: Self.graphQLIntId(product.size?.id)
        )
    }
}
