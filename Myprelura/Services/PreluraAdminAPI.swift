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
        let allReports: [AdminReportRow]?
    }

    static func allReports(client: GraphQLClient) async throws -> [AdminReportRow] {
        let q = """
        query AllReports {
          allReports {
            id publicId reportType reason context imagesUrl status dateCreated updatedAt
            reportedByUsername accountReportedUsername productId productName
            supportConversationId conversationId
          }
        }
        """
        let env: ReportsEnvelope = try await client.execute(query: q, responseType: ReportsEnvelope.self)
        return env.allReports ?? []
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

    // MARK: - Listings (staff: optional `filters.status` ACTIVE | SOLD; default ACTIVE on backend)

    struct ProductsPageEnvelope: Decodable {
        let allProducts: [ProductBrowseRow]?
    }

    /// Paginated slice. Pass `statusFilter: nil` for default **ACTIVE** marketplace slice (same as shoppers). Staff may pass **SOLD** for moderation.
    static func allProductsPage(
        client: GraphQLClient,
        page: Int,
        pageSize: Int,
        statusFilter: String? = nil
    ) async throws -> (rows: [ProductBrowseRow], hasMore: Bool) {
        let q = """
        query Products($pageCount: Int!, $pageNumber: Int!, $filters: ProductFiltersInput) {
          allProducts(pageCount: $pageCount, pageNumber: $pageNumber, filters: $filters) {
            id name listingCode status price imagesUrl seller { username }
          }
        }
        """
        var vars: [String: Any] = ["pageCount": pageSize, "pageNumber": page]
        if let statusFilter {
            vars["filters"] = ["status": statusFilter]
        } else {
            vars["filters"] = NSNull()
        }
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
}
