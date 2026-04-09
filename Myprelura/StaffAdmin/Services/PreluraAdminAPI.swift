import Foundation

enum PreluraAdminAPI {

    // MARK: - Auth

    struct AdminLoginEnvelope: Decodable {
        let adminLogin: AdminLoginPayload?
    }

    struct AdminLoginPayload: Decodable {
        let success: Bool?
        let token: String?
        let refreshToken: String?
        let user: AdminLoginUser?
    }

    struct AdminLoginUser: Decodable {
        let id: Int?
        let username: String?
        let email: String?
    }

    static func adminLogin(client: GraphQLClient, username: String, password: String) async throws -> AdminLoginPayload {
        let q = """
        mutation AdminLogin($username: String!, $password: String!) {
          adminLogin(username: $username, password: $password) {
            success
            token
            refreshToken
            user { id username email }
          }
        }
        """
        let vars: [String: Any] = ["username": username, "password": password]
        let env: AdminLoginEnvelope = try await client.execute(query: q, variables: vars, responseType: AdminLoginEnvelope.self)
        guard let payload = env.adminLogin, payload.token != nil, payload.refreshToken != nil else {
            throw GraphQLError.graphQLErrors([GraphQLErrorResponse(message: "Admin login failed")])
        }
        return payload
    }

    struct ViewMeEnvelope: Decodable {
        let viewMe: ViewMeDTO?
    }

    static func viewMe(client: GraphQLClient) async throws -> ViewMeDTO? {
        let q = """
        query ViewMe {
          viewMe {
            id username email isStaff isSuperuser
          }
        }
        """
        let env: ViewMeEnvelope = try await client.execute(query: q, responseType: ViewMeEnvelope.self)
        return env.viewMe
    }

    // MARK: - Dashboard

    struct AnalyticsEnvelope: Decodable {
        let analyticsOverview: AnalyticsOverviewDTO?
    }

    static func analyticsOverview(client: GraphQLClient) async throws -> AnalyticsOverviewDTO? {
        let q = """
        query Analytics {
          analyticsOverview {
            totalProductViews totalProductViewsToday totalUsers totalNewUsersToday
            totalUsersPercentageChange totalProductViewsPercentageChange
            totalProductViewsBeforeTodayPercentage newUsersPercentageChange
          }
        }
        """
        let env: AnalyticsEnvelope = try await client.execute(query: q, responseType: AnalyticsEnvelope.self)
        return env.analyticsOverview
    }

    struct ReportsEnvelope: Decodable {
        let allReports: [StaffAdminReportRow]?
    }

    static func allReports(client: GraphQLClient) async throws -> [StaffAdminReportRow] {
        let q = """
        query AllReports {
          allReports {
            id publicId reportType reason context imagesUrl status dateCreated updatedAt
            reportedByUsername accountReportedUsername productId productName
            supportConversationId conversationId orderId sellerSupportConversationId
          }
        }
        """
        let env: ReportsEnvelope = try await client.execute(query: q, responseType: ReportsEnvelope.self)
        return env.allReports ?? []
    }

    struct DeleteProductEnvelope: Decodable {
        let deleteProduct: DeleteProductStaffResult?
    }

    struct DeleteProductStaffResult: Decodable {
        let success: Bool?
        let message: String?
    }

    static func deleteProduct(client: GraphQLClient, productId: Int) async throws {
        let q = """
        mutation DeleteProductStaff($productId: Int!) {
          deleteProduct(productId: $productId) {
            success
            message
          }
        }
        """
        let env: DeleteProductEnvelope = try await client.execute(
            query: q,
            variables: ["productId": productId],
            responseType: DeleteProductEnvelope.self
        )
        guard env.deleteProduct?.success == true else {
            let msg = env.deleteProduct?.message ?? "Failed to delete listing"
            throw GraphQLError.graphQLErrors([GraphQLErrorResponse(message: msg)])
        }
    }

    // MARK: - Users

    struct UserStatsEnvelope: Decodable {
        let userAdminStats: [UserAdminRow]?
    }

    static func userAdminStats(client: GraphQLClient, search: String?, page: Int, pageSize: Int) async throws -> [UserAdminRow] {
        let q = """
        query UserStats($search: String, $pageCount: Int, $pageNumber: Int) {
          userAdminStats(search: $search, pageCount: $pageCount, pageNumber: $pageNumber) {
            id username email displayName firstName lastName isVerified isStaff isSuperuser
            activeListings totalListings totalSales totalShopValue
            thumbnailUrl profilePictureUrl dateJoined lastLogin lastSeen
            noOfFollowers noOfFollowing credit
          }
        }
        """
        let vars: [String: Any] = [
            "search": search as Any,
            "pageCount": pageSize,
            "pageNumber": page,
        ]
        let env: UserStatsEnvelope = try await client.execute(query: q, variables: vars, responseType: UserStatsEnvelope.self)
        return env.userAdminStats ?? []
    }

    struct GetUserEnvelope: Decodable {
        let getUser: UserProfileDTO?
    }

    static func getUser(client: GraphQLClient, username: String) async throws -> UserProfileDTO? {
        let q = """
        query GetUser($username: String!) {
          getUser(username: $username) {
            id username email firstName lastName displayName bio isVerified listing
            dateJoined lastLogin lastSeen thumbnailUrl profilePictureUrl
            noOfFollowers noOfFollowing credit
            reviewStats { noOfReviews rating }
          }
        }
        """
        let env: GetUserEnvelope = try await client.execute(
            query: q,
            variables: ["username": username],
            responseType: GetUserEnvelope.self
        )
        return env.getUser
    }

    struct UserProductsEnvelope: Decodable {
        let userProducts: [ProductBrowseRow]?
    }

    /// Active listings for a seller (`userProducts`); same shape as marketplace browse rows.
    static func userProductsPage(
        client: GraphQLClient,
        username: String,
        page: Int,
        pageSize: Int
    ) async throws -> (rows: [ProductBrowseRow], hasMore: Bool) {
        let q = """
        query UserShop($username: String!, $pageCount: Int!, $pageNumber: Int!) {
          userProducts(username: $username, pageCount: $pageCount, pageNumber: $pageNumber) {
            id name listingCode status createdAt price imagesUrl seller { username }
          }
        }
        """
        let vars: [String: Any] = [
            "username": username,
            "pageCount": pageSize,
            "pageNumber": page,
        ]
        let env: UserProductsEnvelope = try await client.execute(query: q, variables: vars, responseType: UserProductsEnvelope.self)
        let rows = env.userProducts ?? []
        let hasMore = rows.count >= pageSize
        return (rows, hasMore)
    }

    // MARK: - Listings (staff: optional `filters.status` ACTIVE | SOLD; default ACTIVE on backend)

    struct ProductsPageEnvelope: Decodable {
        let allProducts: [ProductBrowseRow]?
    }

    /// Paginated slice. Pass `statusFilter: nil` for default **ACTIVE** marketplace slice (same as shoppers). Staff may pass **SOLD** for moderation.
    /// `sort`: `NEWEST` | `PRICE_ASC` | `PRICE_DESC` (GraphQL `SortEnum`). Defaults to **NEWEST** for stable staff ordering.
    static func allProductsPage(
        client: GraphQLClient,
        page: Int,
        pageSize: Int,
        statusFilter: String? = nil,
        sort: String = "NEWEST",
        search: String? = nil,
        minPrice: Double? = nil,
        maxPrice: Double? = nil
    ) async throws -> (rows: [ProductBrowseRow], hasMore: Bool) {
        let q = """
        query Products($pageCount: Int!, $pageNumber: Int!, $filters: ProductFiltersInput, $sort: SortEnum, $search: String) {
          allProducts(pageCount: $pageCount, pageNumber: $pageNumber, filters: $filters, sort: $sort, search: $search) {
            id name listingCode status createdAt price imagesUrl seller { username }
          }
        }
        """
        var vars: [String: Any] = [
            "pageCount": pageSize,
            "pageNumber": page,
            "sort": sort,
        ]
        var filters: [String: Any] = [:]
        if let statusFilter {
            filters["status"] = statusFilter
        }
        if let minPrice {
            filters["minPrice"] = minPrice
        }
        if let maxPrice {
            filters["maxPrice"] = maxPrice
        }
        vars["filters"] = filters.isEmpty ? NSNull() : filters
        let trimmedSearch = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        vars["search"] = trimmedSearch.isEmpty ? NSNull() : trimmedSearch
        let env: ProductsPageEnvelope = try await client.execute(query: q, variables: vars, responseType: ProductsPageEnvelope.self)
        let rows = env.allProducts ?? []
        let hasMore = rows.count >= pageSize
        return (rows, hasMore)
    }

    struct FlagProductEnvelope: Decodable {
        let flagProduct: FlagProductResult?
    }

    struct FlagProductResult: Decodable {
        let success: Bool?
        let message: String?
    }

    static func flagProduct(
        client: GraphQLClient,
        productId: String,
        reason: String,
        flagType: String,
        notes: String?
    ) async throws -> FlagProductResult {
        let q = """
        mutation FlagProduct($id: ID!, $reason: ProductFlagReasonEnum!, $flagType: ProductFlagTypeEnum!, $notes: String) {
          flagProduct(id: $id, reason: $reason, flagType: $flagType, notes: $notes) {
            success message
          }
        }
        """
        let vars: [String: Any] = [
            "id": productId,
            "reason": reason,
            "flagType": flagType,
            "notes": notes as Any,
        ]
        let env: FlagProductEnvelope = try await client.execute(query: q, variables: vars, responseType: FlagProductEnvelope.self)
        return env.flagProduct ?? FlagProductResult(success: false, message: nil)
    }

    // MARK: - Orders

    struct OrdersPageEnvelope: Decodable {
        let adminAllOrders: [AdminOrderRow]?
        let adminAllOrdersTotalNumber: Int?
    }

    static func adminOrdersPage(client: GraphQLClient, page: Int, pageSize: Int) async throws -> (rows: [AdminOrderRow], total: Int) {
        let q = """
        query AdminOrders($pageCount: Int!, $pageNumber: Int!) {
          adminAllOrders(pageCount: $pageCount, pageNumber: $pageNumber) {
            id priceTotal status createdAt
            user { username }
          }
          adminAllOrdersTotalNumber
        }
        """
        let vars: [String: Any] = ["pageCount": pageSize, "pageNumber": page]
        let env: OrdersPageEnvelope = try await client.execute(query: q, variables: vars, responseType: OrdersPageEnvelope.self)
        return (env.adminAllOrders ?? [], env.adminAllOrdersTotalNumber ?? 0)
    }

    /// First line item’s product id for staff chat headers (`adminOrder` is staff-authenticated).
    struct AdminOrderProductPeekEnvelope: Decodable {
        let adminOrder: AdminOrderProductPeek?
    }

    struct AdminOrderProductPeek: Decodable {
        let lineItems: [AdminOrderProductPeekLine]?
    }

    struct AdminOrderProductPeekLine: Decodable {
        let productId: Int?
    }

    static func adminOrderFirstProductId(client: GraphQLClient, orderId: Int) async throws -> Int? {
        let q = """
        query AdminOrderProductPeek($orderId: Int!) {
          adminOrder(orderId: $orderId) {
            lineItems { productId }
          }
        }
        """
        let env: AdminOrderProductPeekEnvelope = try await client.execute(
            query: q,
            variables: ["orderId": orderId],
            responseType: AdminOrderProductPeekEnvelope.self
        )
        return env.adminOrder?.lineItems?.first?.productId
    }

    // MARK: - Banners

    struct BannersEnvelope: Decodable {
        let banners: [BannerRow]?
    }

    static func banners(client: GraphQLClient) async throws -> [BannerRow] {
        let q = """
        query Banners {
          banners { id title season isActive bannerUrl }
        }
        """
        let env: BannersEnvelope = try await client.execute(query: q, responseType: BannersEnvelope.self)
        return env.banners ?? []
    }

    // MARK: - Flag user (admin-only in UI; backend marks user deleted)

    struct FlagUserEnvelope: Decodable {
        let flagUser: FlagUserResult?
    }

    struct FlagUserResult: Decodable {
        let success: Bool?
        let message: String?
    }

    static func flagUser(client: GraphQLClient, userId: String, reason: String, notes: String?) async throws -> FlagUserResult {
        let q = """
        mutation FlagUser($id: ID!, $reason: FlagUserReasonEnum!, $notes: String) {
          flagUser(id: $id, reason: $reason, notes: $notes) {
            success message
          }
        }
        """
        let vars: [String: Any] = ["id": userId, "reason": reason, "notes": notes as Any]
        let env: FlagUserEnvelope = try await client.execute(query: q, variables: vars, responseType: FlagUserEnvelope.self)
        return env.flagUser ?? FlagUserResult(success: false, message: nil)
    }

    // MARK: - User moderation (staff dashboard)

    struct AdminUserModerationEnvelope: Decodable {
        let adminSuspendUser: AdminUserModerationResult?
    }

    struct AdminUserBanEnvelope: Decodable {
        let adminBanUser: AdminUserModerationResult?
    }

    struct AdminUserModerationResult: Decodable {
        let success: Bool?
        let message: String?
    }

    static func adminSuspendUser(client: GraphQLClient, userId: Int) async throws -> AdminUserModerationResult {
        let q = """
        mutation AdminSuspendUser($userId: Int!) {
          adminSuspendUser(userId: $userId) {
            success
            message
          }
        }
        """
        let env: AdminUserModerationEnvelope = try await client.execute(
            query: q,
            variables: ["userId": userId],
            responseType: AdminUserModerationEnvelope.self
        )
        return env.adminSuspendUser ?? AdminUserModerationResult(success: false, message: nil)
    }

    static func adminBanUser(client: GraphQLClient, userId: Int) async throws -> AdminUserModerationResult {
        let q = """
        mutation AdminBanUser($userId: Int!) {
          adminBanUser(userId: $userId) {
            success
            message
          }
        }
        """
        let env: AdminUserBanEnvelope = try await client.execute(
            query: q,
            variables: ["userId": userId],
            responseType: AdminUserBanEnvelope.self
        )
        return env.adminBanUser ?? AdminUserModerationResult(success: false, message: nil)
    }

    struct AdminUserUnsuspendEnvelope: Decodable {
        let adminUnsuspendUser: AdminUserModerationResult?
    }

    struct AdminUserUnbanEnvelope: Decodable {
        let adminUnbanUser: AdminUserModerationResult?
    }

    static func adminUnsuspendUser(client: GraphQLClient, userId: Int) async throws -> AdminUserModerationResult {
        let q = """
        mutation AdminUnsuspendUser($userId: Int!) {
          adminUnsuspendUser(userId: $userId) {
            success
            message
          }
        }
        """
        let env: AdminUserUnsuspendEnvelope = try await client.execute(
            query: q,
            variables: ["userId": userId],
            responseType: AdminUserUnsuspendEnvelope.self
        )
        return env.adminUnsuspendUser ?? AdminUserModerationResult(success: false, message: nil)
    }

    static func adminUnbanUser(client: GraphQLClient, userId: Int) async throws -> AdminUserModerationResult {
        let q = """
        mutation AdminUnbanUser($userId: Int!) {
          adminUnbanUser(userId: $userId) {
            success
            message
          }
        }
        """
        let env: AdminUserUnbanEnvelope = try await client.execute(
            query: q,
            variables: ["userId": userId],
            responseType: AdminUserUnbanEnvelope.self
        )
        return env.adminUnbanUser ?? AdminUserModerationResult(success: false, message: nil)
    }

    // MARK: - Chat (same `conversation` query as consumer; staff may read system/order threads)

    struct ConversationMessagesEnvelope: Decodable {
        let conversation: [ChatMessageDTO]?
    }

    static func conversationMessages(
        client: GraphQLClient,
        conversationId: Int,
        page: Int = 1,
        pageSize: Int = 200
    ) async throws -> [ChatMessageDTO] {
        let q = """
        query ConvMsgs($id: ID!, $pageCount: Int, $pageNumber: Int) {
          conversation(id: $id, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            text
            createdAt
            sender { username }
          }
        }
        """
        let vars: [String: Any] = [
            "id": "\(conversationId)",
            "pageCount": pageSize,
            "pageNumber": page,
        ]
        let env: ConversationMessagesEnvelope = try await client.execute(
            query: q,
            variables: vars,
            responseType: ConversationMessagesEnvelope.self
        )
        return env.conversation ?? []
    }

    // MARK: - Discover featured (consumer strip; staff sets order, max 20)

    struct DiscoverFeaturedEnvelope: Decodable {
        let discoverFeaturedProducts: [ProductBrowseRow]?
    }

    static func discoverFeaturedProductRows(client: GraphQLClient) async throws -> [ProductBrowseRow] {
        let q = """
        query DiscoverFeaturedAdmin {
          discoverFeaturedProducts {
            id name listingCode status createdAt price imagesUrl seller { username }
          }
        }
        """
        let env: DiscoverFeaturedEnvelope = try await client.execute(query: q, responseType: DiscoverFeaturedEnvelope.self)
        return env.discoverFeaturedProducts ?? []
    }

    struct SetDiscoverFeaturedEnvelope: Decodable {
        let setDiscoverFeaturedProducts: SetDiscoverFeaturedPayload?
    }

    struct SetDiscoverFeaturedPayload: Decodable {
        let success: Bool?
        let message: String?
    }

    static func setDiscoverFeaturedProducts(client: GraphQLClient, productIds: [Int]) async throws {
        let q = """
        mutation SetDiscoverFeatured($productIds: [Int!]!) {
          setDiscoverFeaturedProducts(productIds: $productIds) {
            success
            message
          }
        }
        """
        let env: SetDiscoverFeaturedEnvelope = try await client.execute(
            query: q,
            variables: ["productIds": productIds],
            responseType: SetDiscoverFeaturedEnvelope.self
        )
        guard env.setDiscoverFeaturedProducts?.success == true else {
            let msg = env.setDiscoverFeaturedProducts?.message ?? "Failed to update featured products"
            throw GraphQLError.graphQLErrors([GraphQLErrorResponse(message: msg)])
        }
    }

    // MARK: - Order issues (master remote: refund / decline while pending)

    struct AllOrderIssuesEnvelope: Decodable {
        let allOrderIssues: [StaffOrderIssueRow]?
    }

    static func allOrderIssues(client: GraphQLClient) async throws -> [StaffOrderIssueRow] {
        let q = """
        query AllOrderIssues {
          allOrderIssues {
            id
            publicId
            issueType
            description
            status
            resolution
            returnPostagePaidBy
            createdAt
            order { id user { username } seller { username } }
            raisedBy { username }
          }
        }
        """
        let env: AllOrderIssuesEnvelope = try await client.execute(query: q, responseType: AllOrderIssuesEnvelope.self)
        return env.allOrderIssues ?? []
    }

    struct AdminResolveOrderIssueEnvelope: Decodable {
        let adminResolveOrderIssue: AdminResolveOrderIssuePayload?
    }

    struct AdminResolveOrderIssuePayload: Decodable {
        let success: Bool?
        let message: String?
    }

    static func adminResolveOrderIssue(
        client: GraphQLClient,
        issueId: Int,
        status: String,
        resolution: String?,
        returnPostagePaidBy: String?
    ) async throws {
        let q = """
        mutation AdminResolveOrderIssue(
          $issueId: Int!
          $status: String!
          $resolution: String
          $returnPostagePaidBy: String
        ) {
          adminResolveOrderIssue(
            issueId: $issueId
            status: $status
            resolution: $resolution
            returnPostagePaidBy: $returnPostagePaidBy
          ) {
            success
            message
          }
        }
        """
        var vars: [String: Any] = [
            "issueId": issueId,
            "status": status,
        ]
        vars["resolution"] = resolution.map { $0 as Any } ?? NSNull()
        vars["returnPostagePaidBy"] = returnPostagePaidBy.map { $0 as Any } ?? NSNull()
        let env: AdminResolveOrderIssueEnvelope = try await client.execute(
            query: q,
            variables: vars,
            responseType: AdminResolveOrderIssueEnvelope.self
        )
        guard env.adminResolveOrderIssue?.success == true else {
            let msg = env.adminResolveOrderIssue?.message ?? "Could not update issue"
            throw GraphQLError.graphQLErrors([GraphQLErrorResponse(message: msg)])
        }
    }
}
