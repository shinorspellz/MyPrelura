import Foundation
import Combine

/// Admin-only API: resolve users by search (userAdminStats), flag/delete user (flagUser). Requires staff auth token.
@MainActor
class AdminService: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var client: GraphQLClient

    init(client: GraphQLClient) {
        self.client = client
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
    }

    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }

    /// Fetch users for admin (search by username etc). Returns id and username for delete flow.
    func fetchUserAdminStats(search: String?, pageCount: Int = 20, pageNumber: Int = 1) async throws -> [AdminUserEntry] {
        let query = """
        query UserAdminStats($search: String, $pageCount: Int, $pageNumber: Int) {
          userAdminStats(search: $search, pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            username
          }
        }
        """
        var variables: [String: Any] = ["pageCount": pageCount, "pageNumber": pageNumber]
        if let s = search, !s.isEmpty {
            variables["search"] = s
        }
        struct Payload: Decodable {
            let userAdminStats: [AdminUserEntry]?
        }
        let response: Payload = try await client.execute(
            query: query,
            variables: variables,
            responseType: Payload.self
        )
        return response.userAdminStats ?? []
    }

    /// Flag/delete user (soft-delete). Admin only. id is the user's ID (string or int).
    func flagUser(id: String, reason: String, notes: String?) async throws -> (success: Bool, message: String?) {
        let mutation = """
        mutation FlagUser($id: ID!, $reason: FlagUserReasonEnum!, $notes: String) {
          flagUser(id: $id, reason: $reason, notes: $notes) {
            success
            message
          }
        }
        """
        var variables: [String: Any] = ["id": id, "reason": reason]
        if let n = notes, !n.isEmpty {
            variables["notes"] = n
        }
        struct Payload: Decodable {
            let flagUser: FlagUserResult?
        }
        struct FlagUserResult: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: variables,
            responseType: Payload.self
        )
        let result = response.flagUser
        return (result?.success ?? false, result?.message)
    }

    /// Staff-only: all order issues with support thread id for admin replies.
    func fetchAllOrderIssues() async throws -> [AdminOrderIssueRow] {
        let query = AdminGraphQLQueries.allOrderIssues
        struct Payload: Decodable { let allOrderIssues: [AdminOrderIssueRow]? }
        let decoder = JSONDecoder()
        let response: Payload = try await client.execute(
            query: query,
            variables: nil,
            responseType: Payload.self,
            decoder: decoder
        )
        return response.allOrderIssues ?? []
    }

    /// Staff: resolve / decline / reopen an order issue (not limited to seller).
    func adminResolveOrderIssue(issueId: Int, status: String, resolution: String?) async throws -> (success: Bool, message: String?) {
        let mutation = """
        mutation AdminResolveOrderIssue($issueId: Int!, $status: String!, $resolution: String) {
          adminResolveOrderIssue(issueId: $issueId, status: $status, resolution: $resolution) {
            success
            message
          }
        }
        """
        var variables: [String: Any] = ["issueId": issueId, "status": status]
        if let r = resolution, !r.isEmpty { variables["resolution"] = r }
        struct Payload: Decodable {
            let adminResolveOrderIssue: AdminMutationResult?
        }
        struct AdminMutationResult: Decodable {
            let success: Bool?
            let message: String?
        }
        let decoder = JSONDecoder()
        let response: Payload = try await client.execute(
            query: mutation,
            variables: variables,
            responseType: Payload.self,
            decoder: decoder
        )
        let r = response.adminResolveOrderIssue
        return (r?.success ?? false, r?.message)
    }

    /// Staff-only: paginated list of all orders (newest first).
    func fetchAdminAllOrders(pageCount: Int = 50, pageNumber: Int = 1) async throws -> [AdminOrderListRow] {
        let query = """
        query AdminAllOrders($pageCount: Int, $pageNumber: Int) {
          adminAllOrders(pageCount: $pageCount, pageNumber: $pageNumber) {
            id
            publicId
            status
            createdAt
            updatedAt
            priceTotal
            user { username }
            seller { username }
          }
        }
        """
        let variables: [String: Any] = ["pageCount": pageCount, "pageNumber": pageNumber]
        struct Payload: Decodable { let adminAllOrders: [AdminOrderListRow]? }
        let response: Payload = try await client.execute(
            query: query,
            variables: variables,
            responseType: Payload.self
        )
        return response.adminAllOrders ?? []
    }

    /// Staff-only: full order snapshot for admin detail screen.
    func fetchAdminOrder(orderId: Int) async throws -> AdminOrderDetailSnapshot? {
        let query = """
        query AdminOrder($orderId: Int!) {
          adminOrder(orderId: $orderId) {
            \(Self.adminOrderDetailSelection)
          }
        }
        """
        struct Payload: Decodable { let adminOrder: AdminOrderDetailSnapshot? }
        let response: Payload = try await client.execute(
            query: query,
            variables: ["orderId": orderId],
            responseType: Payload.self
        )
        return response.adminOrder
    }

    func adminMarkOrderDelivered(orderId: Int) async throws -> (success: Bool, message: String?) {
        let mutation = """
        mutation AdminMarkOrderDelivered($orderId: Int!) {
          adminMarkOrderDelivered(orderId: $orderId) {
            success
            message
          }
        }
        """
        struct Payload: Decodable {
            let adminMarkOrderDelivered: AdminMutationSimple?
        }
        struct AdminMutationSimple: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId],
            responseType: Payload.self
        )
        let r = response.adminMarkOrderDelivered
        return (r?.success ?? false, r?.message)
    }

    func adminMarkOrderComplete(orderId: Int) async throws -> (success: Bool, message: String?) {
        let mutation = """
        mutation AdminMarkOrderComplete($orderId: Int!) {
          adminMarkOrderComplete(orderId: $orderId) {
            success
            message
          }
        }
        """
        struct Payload: Decodable {
            let adminMarkOrderComplete: AdminMutationSimple?
        }
        struct AdminMutationSimple: Decodable {
            let success: Bool?
            let message: String?
        }
        let response: Payload = try await client.execute(
            query: mutation,
            variables: ["orderId": orderId],
            responseType: Payload.self
        )
        let r = response.adminMarkOrderComplete
        return (r?.success ?? false, r?.message)
    }

    /// GraphQL selection for a full admin `Order` (matches `AdminOrderDetailSnapshot`).
    private static let adminOrderDetailSelection = """
    id
    publicId
    status
    createdAt
    updatedAt
    priceTotal
    discountPrice
    buyerProtectionFee
    shippingFee
    itemsSubtotal
    shippingAddressJson
    orderConversationId
    trackingNumber
    trackingUrl
    carrierName
    shippingLabelUrl
    shipmentEstimatedDelivery
    shipmentActualDelivery
    shipmentInternalStatus
    shipmentService
    user { username }
    seller { username }
    offer { id status }
    cancelledOrder {
      buyerCancellationReason
      sellerResponse
      status
      notes
    }
    lineItems {
      id
      productId
      productName
      priceAtPurchase
      productImagesUrl
    }
    payments {
      id
      paymentRef
      paymentStatus
      paymentAmount
      paymentMethod
      paymentIntentId
      createdAt
      updatedAt
    }
    refunds {
      id
      refundAmount
      status
      reason
      refundedAt
      createdAt
    }
    statusTimeline {
      id
      status
      createdAt
    }
    """

    func fetchAllReports() async throws -> [AdminReportRow] {
        let query = """
        query AllReports {
          allReports {
            id
            publicId
            reportType
            reason
            context
            imagesUrl
            status
            dateCreated
            updatedAt
            reportedByUsername
            accountReportedUsername
            productId
            productName
            conversationId
          }
        }
        """
        struct Payload: Decodable { let allReports: [AdminReportRow]? }
        let response: Payload = try await client.execute(query: query, variables: nil, responseType: Payload.self)
        return response.allReports ?? []
    }
}

private enum AdminGraphQLQueries {
    static let allOrderIssues = """
    query AllOrderIssues {
      allOrderIssues {
        id
        publicId
        issueType
        description
        imagesUrl
        status
        resolution
        resolvedAt
        createdAt
        updatedAt
        raisedBy { username }
        resolvedBy { username }
        order {
          id
          publicId
          status
          createdAt
          updatedAt
          priceTotal
          discountPrice
          buyerProtectionFee
          shippingFee
          itemsSubtotal
          shippingAddressJson
          orderConversationId
          trackingNumber
          trackingUrl
          carrierName
          shippingLabelUrl
          shipmentEstimatedDelivery
          shipmentActualDelivery
          shipmentInternalStatus
          shipmentService
          user { username }
          seller { username }
          offer { id status }
          cancelledOrder {
            buyerCancellationReason
            sellerResponse
            status
            notes
          }
          lineItems {
            id
            productId
            productName
            priceAtPurchase
            productImagesUrl
          }
          payments {
            id
            paymentRef
            paymentStatus
            paymentAmount
            paymentMethod
            paymentIntentId
            createdAt
            updatedAt
          }
          refunds {
            id
            refundAmount
            status
            reason
            refundedAt
            createdAt
          }
          statusTimeline {
            id
            status
            createdAt
          }
        }
        supportConversationId
        sellerSupportConversationId
      }
    }
    """
}

/// One row from `allOrderIssues` (admin).
struct AdminOrderIssueRow: Decodable, Identifiable {
    struct RaisedByRef: Decodable { let username: String? }
    struct ResolvedByRef: Decodable { let username: String? }

    let id: Int
    let publicId: String?
    let issueType: String?
    let description: String?
    let imagesUrl: [String]?
    let status: String?
    let resolution: String?
    let resolvedAt: String?
    let createdAt: String?
    let updatedAt: String?
    let raisedBy: RaisedByRef?
    let resolvedBy: ResolvedByRef?
    let order: AdminOrderDetailSnapshot?
    let supportConversationId: Int?
    /// Seller ↔ support thread (when seller tapped Contact support).
    let sellerSupportConversationId: Int?

    enum CodingKeys: String, CodingKey {
        case id, publicId, issueType, description, imagesUrl, status, resolution, resolvedAt
        case createdAt, updatedAt, raisedBy, resolvedBy, order, supportConversationId
        case sellerSupportConversationId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "Expected Int or numeric String for issue id")
        }
        publicId = try c.decodeIfPresent(String.self, forKey: .publicId)
        issueType = try c.decodeIfPresent(String.self, forKey: .issueType)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        if let arr = try? c.decode([String].self, forKey: .imagesUrl) {
            imagesUrl = arr
        } else {
            imagesUrl = []
        }
        status = try c.decodeIfPresent(String.self, forKey: .status)
        resolution = try c.decodeIfPresent(String.self, forKey: .resolution)
        resolvedAt = try c.decodeIfPresent(String.self, forKey: .resolvedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        raisedBy = try c.decodeIfPresent(RaisedByRef.self, forKey: .raisedBy)
        resolvedBy = try c.decodeIfPresent(ResolvedByRef.self, forKey: .resolvedBy)
        order = try c.decodeIfPresent(AdminOrderDetailSnapshot.self, forKey: .order)
        if let i = try? c.decode(Int.self, forKey: .supportConversationId) {
            supportConversationId = i
        } else if let s = try? c.decode(String.self, forKey: .supportConversationId), let i = Int(s) {
            supportConversationId = i
        } else {
            supportConversationId = nil
        }
        if let i = try? c.decode(Int.self, forKey: .sellerSupportConversationId) {
            sellerSupportConversationId = i
        } else if let s = try? c.decode(String.self, forKey: .sellerSupportConversationId), let i = Int(s) {
            sellerSupportConversationId = i
        } else {
            sellerSupportConversationId = nil
        }
    }
}

struct AdminUserBrief: Decodable {
    let username: String?
}

struct AdminOrderLineItem: Decodable, Identifiable {
    let id: Int
    let productId: Int?
    let productName: String?
    let priceAtPurchase: Double?
    let productImagesUrl: [String]?

    enum CodingKeys: String, CodingKey {
        case id, productId, productName, priceAtPurchase, productImagesUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "line item id")
        }
        if let i = try? c.decode(Int.self, forKey: .productId) {
            productId = i
        } else if let s = try? c.decode(String.self, forKey: .productId), let i = Int(s) {
            productId = i
        } else {
            productId = nil
        }
        productName = try c.decodeIfPresent(String.self, forKey: .productName)
        priceAtPurchase = try c.decodeAdminMoney(forKey: .priceAtPurchase)
        productImagesUrl = c.decodeLossyProductImageURLs(forKey: .productImagesUrl)
    }
}

struct AdminOrderPaymentRow: Decodable, Identifiable {
    let id: Int
    let paymentRef: String?
    let paymentStatus: String?
    let paymentAmount: Double?
    let paymentMethod: String?
    let paymentIntentId: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, paymentRef, paymentStatus, paymentAmount, paymentMethod, paymentIntentId, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "payment id")
        }
        paymentRef = try c.decodeIfPresent(String.self, forKey: .paymentRef)
        paymentStatus = try c.decodeIfPresent(String.self, forKey: .paymentStatus)
        paymentAmount = try c.decodeAdminMoney(forKey: .paymentAmount)
        paymentMethod = try c.decodeIfPresent(String.self, forKey: .paymentMethod)
        paymentIntentId = try c.decodeIfPresent(String.self, forKey: .paymentIntentId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
    }
}

struct AdminOrderRefundRow: Decodable, Identifiable {
    let id: Int
    let refundAmount: Double?
    let status: String?
    let reason: String?
    let refundedAt: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, refundAmount, status, reason, refundedAt, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "refund id")
        }
        refundAmount = try c.decodeAdminMoney(forKey: .refundAmount)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        refundedAt = try c.decodeIfPresent(String.self, forKey: .refundedAt)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct AdminOrderStatusEvent: Decodable, Identifiable {
    let id: Int
    let status: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey { case id, status, createdAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let i = try? c.decode(Int.self, forKey: .id) {
            id = i
        } else if let s = try? c.decode(String.self, forKey: .id), let i = Int(s) {
            id = i
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "timeline id")
        }
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

struct AdminOrderOfferRef: Decodable {
    let id: String?
    let status: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            id = nil
        }
        status = try c.decodeIfPresent(String.self, forKey: .status)
    }

    enum CodingKeys: String, CodingKey { case id, status }
}

struct AdminCancelledOrderSnapshot: Decodable {
    let buyerCancellationReason: String?
    let sellerResponse: String?
    let status: String?
    let notes: String?
}

/// Row for `adminAllOrders` list.
struct AdminOrderListRow: Decodable, Identifiable {
    let id: String
    let publicId: String?
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let priceTotal: Double?
    let user: AdminUserBrief?
    let seller: AdminUserBrief?

    enum CodingKeys: String, CodingKey {
        case id, publicId, status, createdAt, updatedAt, priceTotal, user, seller
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "order id")
        }
        publicId = try c.decodeIfPresent(String.self, forKey: .publicId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        priceTotal = try c.decodeAdminMoney(forKey: .priceTotal)
        user = try c.decodeIfPresent(AdminUserBrief.self, forKey: .user)
        seller = try c.decodeIfPresent(AdminUserBrief.self, forKey: .seller)
    }
}

struct AdminOrderDetailSnapshot: Decodable {
    let id: String
    let publicId: String?
    let status: String?
    let createdAt: String?
    let updatedAt: String?
    let priceTotal: Double?
    let discountPrice: Double?
    let buyerProtectionFee: Double?
    let shippingFee: Double?
    let itemsSubtotal: Double?
    let shippingAddressJson: String?
    let orderConversationId: Int?
    let trackingNumber: String?
    let trackingUrl: String?
    let carrierName: String?
    let shippingLabelUrl: String?
    let shipmentEstimatedDelivery: String?
    let shipmentActualDelivery: String?
    let shipmentInternalStatus: String?
    let shipmentService: String?
    let user: AdminUserBrief?
    let seller: AdminUserBrief?
    let offer: AdminOrderOfferRef?
    let cancelledOrder: AdminCancelledOrderSnapshot?
    let lineItems: [AdminOrderLineItem]?
    let payments: [AdminOrderPaymentRow]?
    let refunds: [AdminOrderRefundRow]?
    let statusTimeline: [AdminOrderStatusEvent]?

    enum CodingKeys: String, CodingKey {
        case id, publicId, status, createdAt, updatedAt
        case priceTotal, discountPrice, buyerProtectionFee, shippingFee, itemsSubtotal
        case shippingAddressJson, orderConversationId
        case trackingNumber, trackingUrl, carrierName, shippingLabelUrl
        case shipmentEstimatedDelivery, shipmentActualDelivery, shipmentInternalStatus, shipmentService
        case user, seller, offer, cancelledOrder
        case lineItems, payments, refunds, statusTimeline
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try? c.decode(String.self, forKey: .id) {
            id = s
        } else if let i = try? c.decode(Int.self, forKey: .id) {
            id = String(i)
        } else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "order id")
        }
        publicId = try c.decodeIfPresent(String.self, forKey: .publicId)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        priceTotal = try c.decodeAdminMoney(forKey: .priceTotal)
        discountPrice = try c.decodeAdminMoney(forKey: .discountPrice)
        buyerProtectionFee = try c.decodeAdminMoney(forKey: .buyerProtectionFee)
        shippingFee = try c.decodeAdminMoney(forKey: .shippingFee)
        itemsSubtotal = try c.decodeAdminMoney(forKey: .itemsSubtotal)
        shippingAddressJson = try c.decodeIfPresent(String.self, forKey: .shippingAddressJson)
        if let i = try? c.decode(Int.self, forKey: .orderConversationId) {
            orderConversationId = i
        } else if let s = try? c.decode(String.self, forKey: .orderConversationId), let i = Int(s) {
            orderConversationId = i
        } else {
            orderConversationId = nil
        }
        trackingNumber = try c.decodeIfPresent(String.self, forKey: .trackingNumber)
        trackingUrl = try c.decodeIfPresent(String.self, forKey: .trackingUrl)
        carrierName = try c.decodeIfPresent(String.self, forKey: .carrierName)
        shippingLabelUrl = try c.decodeIfPresent(String.self, forKey: .shippingLabelUrl)
        shipmentEstimatedDelivery = try c.decodeIfPresent(String.self, forKey: .shipmentEstimatedDelivery)
        shipmentActualDelivery = try c.decodeIfPresent(String.self, forKey: .shipmentActualDelivery)
        shipmentInternalStatus = try c.decodeIfPresent(String.self, forKey: .shipmentInternalStatus)
        shipmentService = try c.decodeIfPresent(String.self, forKey: .shipmentService)
        user = try c.decodeIfPresent(AdminUserBrief.self, forKey: .user)
        seller = try c.decodeIfPresent(AdminUserBrief.self, forKey: .seller)
        offer = try c.decodeIfPresent(AdminOrderOfferRef.self, forKey: .offer)
        cancelledOrder = try c.decodeIfPresent(AdminCancelledOrderSnapshot.self, forKey: .cancelledOrder)
        lineItems = (try? c.decode([AdminOrderLineItem].self, forKey: .lineItems))
        payments = (try? c.decode([AdminOrderPaymentRow].self, forKey: .payments))
        refunds = (try? c.decode([AdminOrderRefundRow].self, forKey: .refunds))
        statusTimeline = (try? c.decode([AdminOrderStatusEvent].self, forKey: .statusTimeline))
    }
}

private extension KeyedDecodingContainer {
    /// GraphQL often sends decimals as JSON strings; `decodeIfPresent(Double:)` throws on string values.
    func decodeAdminMoney(forKey key: Key) throws -> Double? {
        guard contains(key) else { return nil }
        if (try? decodeNil(forKey: key)) == true { return nil }
        if let d = try? decode(Double.self, forKey: key) { return d }
        if let s = try? decode(String.self, forKey: key) { return Double(s) }
        if let i = try? decode(Int.self, forKey: key) { return Double(i) }
        return nil
    }

    func decodeLossyProductImageURLs(forKey key: Key) -> [String] {
        guard contains(key) else { return [] }
        if (try? decodeNil(forKey: key)) == true { return [] }
        guard var nested = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var out: [String] = []
        while !nested.isAtEnd {
            if let s = try? nested.decode(String.self) {
                out.append(s)
            } else if let dict = try? nested.decode([String: AnyCodable].self) {
                let urlKeys = ["url", "imageUrl", "image_url", "src", "href", "path", "link"]
                var added = false
                for k in urlKeys {
                    if let v = dict[k]?.value as? String, !v.isEmpty {
                        out.append(v)
                        added = true
                        break
                    }
                }
                if !added {
                    for (_, v) in dict {
                        if let s = v.value as? String, !s.isEmpty, s.contains("http") {
                            out.append(s)
                            break
                        }
                    }
                }
            } else {
                _ = try? nested.decode(AnyCodable.self)
            }
        }
        return out
    }
}

struct AdminUserEntry: Decodable {
    let id: AnyCodable?
    let username: String?

    var idString: String? {
        guard let id = id else { return nil }
        if let intVal = id.value as? Int { return String(intVal) }
        if let strVal = id.value as? String { return strVal }
        return String(describing: id.value)
    }
}

struct AdminReportRow: Decodable, Identifiable, Hashable {
    let rawId: Int
    let publicId: String?
    let reportType: String?
    let reason: String?
    let context: String?
    let imagesUrl: [String]?
    let status: String?
    let dateCreated: String?
    let updatedAt: String?
    let reportedByUsername: String?
    let accountReportedUsername: String?
    let productId: Int?
    let productName: String?
    let conversationId: Int?

    var id: String { "\(reportType ?? "REPORT")-\(rawId)" }

    enum CodingKeys: String, CodingKey {
        case rawId = "id"
        case publicId, reportType, reason, context, imagesUrl, status
        case dateCreated, updatedAt, reportedByUsername, accountReportedUsername
        case productId, productName, conversationId
    }
}
