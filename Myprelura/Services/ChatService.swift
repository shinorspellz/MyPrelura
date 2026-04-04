import Foundation
import Combine

/// Shared ISO8601 parsing for conversation/offer timestamps (used by `ChatService` and `Conversation.offerInfo`).
fileprivate func parseGraphQLDateString(_ dateString: String?) -> Date? {
    guard let dateString = dateString else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: dateString) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: dateString)
}

@MainActor
class ChatService: ObservableObject {
    private var client: GraphQLClient
    
    init(client: GraphQLClient? = nil) {
        self.client = client ?? GraphQLClient()
        // Try to load auth token from UserDefaults
        if let token = UserDefaults.standard.string(forKey: "AUTH_TOKEN") {
            self.client.setAuthToken(token)
        }
    }
    
    func updateAuthToken(_ token: String?) {
        client.setAuthToken(token)
    }
    
    /// Shared selection for inbox + archived inbox rows.
    private static let conversationListFields = """
            id
            recipient {
              id
              username
              displayName
              profilePictureUrl
            }
            lastMessage {
              id
              text
              createdAt
              sender { username }
            }
            unreadMessagesCount
            offer {
              id
              status
              offerPrice
              createdBy
              updatedBy
              buyer { username profilePictureUrl }
              products { id name seller { username profilePictureUrl } }
              createdAt
            }
            order {
              id
              publicId
              status
              priceTotal
              createdAt
              products { id name imagesUrl price }
            }
    """

    /// Conversations list. Includes offer when present (for offer card in chat).
    func getConversations() async throws -> [Conversation] {
        let query = """
        query Conversations {
          conversations {
        \(Self.conversationListFields)
          }
        }
        """

        let response: ConversationsResponse
        do {
            response = try await client.execute(
                query: query,
                operationName: "Conversations",
                responseType: ConversationsResponse.self
            )
        } catch let err as GraphQLError {
            if case .decodingError = err { return [] }
            throw err
        } catch {
            throw error
        }

        return Self.mapConversationDataRows(response.conversations)
    }

    /// Threads the user archived (same row shape as `conversations`).
    func getArchivedConversations() async throws -> [Conversation] {
        let query = """
        query ArchivedConversations {
          archivedConversations {
        \(Self.conversationListFields)
          }
        }
        """
        let response: ArchivedConversationsResponse
        do {
            response = try await client.execute(
                query: query,
                operationName: "ArchivedConversations",
                responseType: ArchivedConversationsResponse.self
            )
        } catch let err as GraphQLError {
            if case .decodingError = err { return [] }
            throw err
        } catch {
            throw error
        }
        return Self.mapConversationDataRows(response.archivedConversations)
    }

    private static func mapConversationOrderData(_ o: ConversationOrderData) -> ConversationOrder? {
        guard let orderIdStr = Conversation.idString(from: o.id), !orderIdStr.isEmpty else { return nil }
        let total = o.priceTotalDouble
        let rows = o.products ?? []
        let lineItems: [ConversationOrderLineSummary] = rows.compactMap { p in
            guard let pid = Conversation.idString(from: p.id) else { return nil }
            return ConversationOrderLineSummary(
                productId: pid,
                name: (p.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                imageUrl: p.firstImageUrl,
                price: p.unitPrice
            )
        }
        let first = lineItems.first
        let firstName = first?.name.isEmpty == false ? first?.name : rows.first?.name
        let firstImg = first?.imageUrl ?? rows.first?.firstImageUrl
        let firstPid = first?.productId ?? rows.first.flatMap { Conversation.idString(from: $0.id) }
        let pub = (o.publicId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ConversationOrder(
            id: orderIdStr,
            publicId: pub.isEmpty ? nil : pub,
            status: o.status ?? "CONFIRMED",
            total: total,
            firstProductName: firstName,
            firstProductImageUrl: firstImg,
            firstProductId: firstPid,
            createdAt: parseGraphQLDateString(o.createdAt),
            lineItems: lineItems
        )
    }

    private static func mapConversationDataRows(_ rows: [ConversationData]?) -> [Conversation] {
        rows?.compactMap { conv in
            guard let idString = Conversation.idString(from: conv.id) else { return nil }
            let recipientIdString: String
            if let recipientId = conv.recipient?.id {
                if let intValue = recipientId.value as? Int { recipientIdString = String(intValue) }
                else if let stringValue = recipientId.value as? String { recipientIdString = stringValue }
                else { recipientIdString = String(describing: recipientId.value) }
            } else {
                recipientIdString = ""
            }
            let offer: OfferInfo? = conv.offer.flatMap { Conversation.offerInfo(from: $0) }
            let order: ConversationOrder? = conv.order.flatMap { Self.mapConversationOrderData($0) }
            let lastTime = parseGraphQLDateString(conv.lastMessage?.createdAt)
                ?? order?.createdAt
                ?? offer?.createdAt
            return Conversation(
                id: idString,
                recipient: User(
                    id: UUID(uuidString: recipientIdString) ?? UUID(),
                    username: conv.recipient?.username ?? "",
                    displayName: conv.recipient?.displayName ?? "",
                    avatarURL: conv.recipient?.profilePictureUrl
                ),
                lastMessage: conv.lastMessage?.text,
                lastMessageSenderUsername: conv.lastMessage?.sender?.username,
                lastMessageTime: lastTime,
                unreadCount: conv.unreadMessagesCount ?? 0,
                offer: offer,
                order: order,
                offerHistory: nil
            )
        } ?? []
    }
    
    /// Fetch a single conversation by id (with order). Sale banner is stored on the backend like offers: Conversation.order FK + Message (item_type=sold_confirmation) created in payment success handler.
    /// - Parameter currentUsername: Used to set `sentByCurrentUser` on each row in `offerHistory`.
    /// - Note: The query requests `offerHistory` on `conversationById`. Deploy the backend GraphQL change before shipping this client build, or the request will fail until the field exists.
    func getConversationById(conversationId: String, currentUsername: String? = nil) async throws -> Conversation? {
        let query = """
        query ConversationById($id: ID!) {
          conversationById(id: $id) {
            id
            recipient {
              id
              username
              displayName
              profilePictureUrl
            }
            lastMessage {
              id
              text
              createdAt
              sender { username }
            }
            unreadMessagesCount
            offer {
              id
              status
              offerPrice
              createdBy
              updatedBy
              buyer { username profilePictureUrl }
              products { id name seller { username profilePictureUrl } }
              createdAt
            }
            offerHistory {
              id
              status
              offerPrice
              createdBy
              updatedBy
              buyer { username profilePictureUrl }
              products { id name seller { username profilePictureUrl } }
              createdAt
            }
            order {
              id
              publicId
              status
              priceTotal
              createdAt
              products { id name imagesUrl price }
            }
          }
        }
        """
        let variables: [String: Any] = ["id": conversationId]
        struct ConversationByIdResponse: Decodable {
            let conversationById: ConversationData?
            enum CodingKeys: String, CodingKey { case conversationById = "conversationById" }
        }
        let response: ConversationByIdResponse = try await client.execute(
            query: query,
            variables: variables,
            operationName: "ConversationById",
            responseType: ConversationByIdResponse.self
        )
        guard let conv = response.conversationById else { return nil }
        guard let idString = Conversation.idString(from: conv.id) else { return nil }
        let recipientIdString: String
        if let recipientId = conv.recipient?.id {
            if let intValue = recipientId.value as? Int { recipientIdString = String(intValue) }
            else if let stringValue = recipientId.value as? String { recipientIdString = stringValue }
            else { recipientIdString = String(describing: recipientId.value) }
        } else {
            recipientIdString = ""
        }
        let offer: OfferInfo? = conv.offer.flatMap { Conversation.offerInfo(from: $0) }
        let order: ConversationOrder? = conv.order.flatMap { Self.mapConversationOrderData($0) }
        let lastTime = parseGraphQLDateString(conv.lastMessage?.createdAt) ?? order?.createdAt
        let offerHistory: [OfferInfo]? = {
            guard let rows = conv.offerHistory, !rows.isEmpty else { return nil }
            return Self.mapOfferHistory(rows, currentUsername: currentUsername)
        }()
        return Conversation(
            id: idString,
            recipient: User(
                id: UUID(uuidString: recipientIdString) ?? UUID(),
                username: conv.recipient?.username ?? "",
                displayName: conv.recipient?.displayName ?? "",
                avatarURL: conv.recipient?.profilePictureUrl
            ),
            lastMessage: conv.lastMessage?.text,
            lastMessageSenderUsername: conv.lastMessage?.sender?.username,
            lastMessageTime: lastTime,
            unreadCount: conv.unreadMessagesCount ?? 0,
            offer: offer,
            order: order,
            offerHistory: offerHistory
        )
    }

    /// Resolve a thread for opening from push or universal link: prefer `conversationById`, then inbox list, else minimal placeholder (correct id preserves the real chat).
    func resolveConversationForOpening(conversationId: String, fallbackUsername: String, currentUsername: String?) async -> Conversation {
        if let full = try? await getConversationById(conversationId: conversationId, currentUsername: currentUsername) {
            return full
        }
        do {
            let convs = try await getConversations()
            if let existing = convs.first(where: { $0.id == conversationId }) {
                return existing
            }
        } catch {}
        let placeholderUser = User(
            id: UUID(),
            username: fallbackUsername,
            displayName: fallbackUsername,
            avatarURL: nil
        )
        return Conversation(
            id: conversationId,
            recipient: placeholderUser,
            lastMessage: nil,
            lastMessageTime: nil,
            unreadCount: 0
        )
    }

    /// Maps server `offerHistory` to UI rows with correct `sentByCurrentUser` from `createdBy` vs current user.
    private static func mapOfferHistory(_ rows: [OfferData], currentUsername: String?) -> [OfferInfo] {
        rows.compactMap { data -> OfferInfo? in
            guard let base = Conversation.offerInfo(from: data) else { return nil }
            let sender = data.createdBy ?? data.buyer?.username
            let fromMe = usernamesMatch(sender, currentUsername)
            return OfferInfo(
                id: base.id,
                backendId: base.backendId,
                status: base.status,
                offerPrice: base.offerPrice,
                buyer: base.buyer,
                products: base.products,
                createdAt: base.createdAt ?? parseGraphQLDateString(data.createdAt),
                sentByCurrentUser: fromMe,
                financialBuyerUsername: base.financialBuyerUsername,
                updatedByUsername: data.updatedBy ?? base.updatedByUsername
            )
        }
    }

    private static func usernamesMatch(_ a: String?, _ b: String?) -> Bool {
        let x = (a ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let y = (b ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !x.isEmpty && !y.isEmpty && x == y
    }
    
    func getMessages(conversationId: String, pageNumber: Int = 1, pageCount: Int = 100) async throws -> [Message] {
        // Backend returns conversation(id:) as [MessageType] directly, not { id, messages }.
        let query = """
        query Conversation($id: ID!, $pageNumber: Int, $pageCount: Int) {
          conversation(id: $id, pageNumber: $pageNumber, pageCount: $pageCount) {
            id
            text
            createdAt
            read
            sender {
              id
              username
              profilePictureUrl
            }
            isItem
            itemId
            itemType
          }
        }
        """
        
        let variables: [String: Any] = [
            "id": conversationId,
            "pageNumber": pageNumber,
            "pageCount": pageCount
        ]
        
        let response: ConversationMessagesResponse = try await client.execute(
            query: query,
            variables: variables,
            responseType: ConversationMessagesResponse.self
        )
        
        guard let messages = response.conversation else {
            return []
        }
        
        let list: [Message] = messages.compactMap { msg in
            // Backend id (Int) for mark-as-read
            let backendIdInt: Int?
            if let anyCodable = msg.id {
                if let intValue = anyCodable.value as? Int {
                    backendIdInt = intValue
                } else if let stringValue = anyCodable.value as? String, let i = Int(stringValue) {
                    backendIdInt = i
                } else {
                    backendIdInt = nil
                }
            } else {
                backendIdInt = nil
            }
            let idString: String
            if let anyCodable = msg.id {
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
            
            // Don't drop messages: use fallbacks so Sold/order cards and item messages always show
            let text = msg.text ?? ""
            let senderUsername = msg.sender?.username ?? "Unknown"
            let messageType: String = (msg.itemType?.isEmpty == false) ? msg.itemType! : (msg.isItem == true ? "item" : "text")
            
            return Message(
                id: backendIdInt.map { Message.stableUUID(forBackendId: $0) } ?? (UUID(uuidString: idString) ?? UUID()),
                backendId: backendIdInt,
                senderUsername: senderUsername,
                content: text,
                timestamp: parseDate(msg.createdAt) ?? Date(),
                type: messageType,
                orderID: msg.itemId.map { String($0) },
                thumbnailURL: nil,
                read: msg.read ?? false
            )
        }
        return list.sorted { $0.timestamp < $1.timestamp }
    }
    
    func createChat(recipient: String) async throws -> Conversation {
        let mutation = """
        mutation CreateChat($recipient: String!) {
          createChat(recipient: $recipient) {
            chat {
              id
              recipient {
                id
                username
                displayName
                profilePictureUrl
              }
            }
          }
        }
        """
        
        let variables: [String: Any] = ["recipient": recipient]
        
        let response: CreateChatResponse = try await client.execute(
            query: mutation,
            variables: variables,
            responseType: CreateChatResponse.self
        )
        
        guard let chat = response.createChat?.chat else {
            throw ChatError.invalidResponse
        }
        let idString: String
        if let anyId = chat.id {
            if let intValue = anyId.value as? Int {
                idString = String(intValue)
            } else if let stringValue = anyId.value as? String {
                idString = stringValue
            } else {
                idString = String(describing: anyId.value)
            }
        } else {
            throw ChatError.invalidResponse
        }
        // Extract recipient id
        let recipientIdString: String
        if let recipientId = chat.recipient?.id {
            if let intValue = recipientId.value as? Int {
                recipientIdString = String(intValue)
            } else if let stringValue = recipientId.value as? String {
                recipientIdString = stringValue
            } else {
                recipientIdString = String(describing: recipientId.value)
            }
        } else {
            recipientIdString = ""
        }
        
        return Conversation(
            id: idString,
            recipient: User(
                id: UUID(uuidString: recipientIdString) ?? UUID(),
                username: chat.recipient?.username ?? "",
                displayName: chat.recipient?.displayName ?? "",
                avatarURL: chat.recipient?.profilePictureUrl
            ),
            lastMessage: nil,
            lastMessageTime: nil,
            unreadCount: 0
        )
    }
    
    /// Send a message (GraphQL fallback when WebSocket is unavailable).
    /// conversationId: backend expects Int; we accept String and pass Int when possible.
    func sendMessage(conversationId: String, message: String, messageUuid: String?) async throws -> Bool {
        let convIdInt = Int(conversationId) ?? 0
        let mutation = """
        mutation SendMessage($conversationId: Int!, $message: String!, $messageUuid: String) {
          sendMessage(conversationId: $conversationId, message: $message, messageUuid: $messageUuid) {
            success
            messageId
          }
        }
        """
        var variables: [String: Any] = ["conversationId": convIdInt, "message": message]
        if let uuid = messageUuid { variables["messageUuid"] = uuid }
        let response: SendMessageResponse = try await client.execute(
            query: mutation,
            variables: variables,
            responseType: SendMessageResponse.self
        )
        return response.sendMessage?.success ?? false
    }
    
    /// Mark messages as read. Matches Flutter readMessages(ids). Call when opening a conversation.
    func readMessages(messageIds: [Int]) async throws -> Bool {
        guard !messageIds.isEmpty else { return true }
        let mutation = """
        mutation UpdateReadMessages($messageIds: [Int]!) {
          updateReadMessages(messageIds: $messageIds) {
            success
          }
        }
        """
        let variables: [String: Any] = ["messageIds": messageIds]
        struct Payload: Decodable { let updateReadMessages: UpdateReadResult? }
        struct UpdateReadResult: Decodable { let success: Bool? }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        return response.updateReadMessages?.success ?? false
    }
    
    /// Create a sold-confirmation message in the order's conversation. Matches Flutter createSoldConfirmationMessage(orderId). Call after seller marks order/item as sold.
    func createSoldConfirmationMessage(orderId: Int) async throws -> (success: Bool, conversationId: Int?) {
        let mutation = """
        mutation CreateSoldConfirmationMessage($orderId: Int!) {
          createSoldConfirmationMessage(orderId: $orderId) {
            success
            messageId
            conversationId
          }
        }
        """
        let variables: [String: Any] = ["orderId": orderId]
        struct Payload: Decodable {
            let createSoldConfirmationMessage: Result?
            struct Result: Decodable {
                let success: Bool?
                let messageId: Int?
                let conversationId: Int?
            }
        }
        let response: Payload = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
        let result = response.createSoldConfirmationMessage
        return (result?.success ?? false, result?.conversationId)
    }
    
    /// Delete a single message. Matches Flutter deleteMessage(messageId). Use message.backendId.
    func deleteMessage(messageId: Int) async throws {
        let mutation = """
        mutation DeleteMessage($messageId: Int!) {
          deleteMessage(messageId: $messageId) {
            message
          }
        }
        """
        let variables: [String: Any] = ["messageId": messageId]
        struct Payload: Decodable { let deleteMessage: Result?; struct Result: Decodable { let message: String? } }
        _ = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
    }
    
    /// Delete a conversation permanently.
    func deleteConversation(conversationId: Int) async throws {
        let mutation = """
        mutation DeleteConversation($conversationId: Int!) {
          deleteConversation(conversationId: $conversationId) {
            message
          }
        }
        """
        let variables: [String: Any] = ["conversationId": conversationId]
        struct Payload: Decodable { let deleteConversation: Result?; struct Result: Decodable { let message: String? } }
        _ = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
    }

    /// Archive for the current user (thread hidden from main inbox).
    func archiveConversation(conversationId: Int) async throws {
        let mutation = """
        mutation ArchiveConversation($conversationId: Int!) {
          archiveConversation(conversationId: $conversationId) {
            message
          }
        }
        """
        let variables: [String: Any] = ["conversationId": conversationId]
        struct Payload: Decodable { let archiveConversation: Result?; struct Result: Decodable { let message: String? } }
        _ = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
    }

    /// Remove from archive (show again in main inbox).
    func unarchiveConversation(conversationId: Int) async throws {
        let mutation = """
        mutation UnarchiveConversation($conversationId: Int!) {
          unarchiveConversation(conversationId: $conversationId) {
            message
          }
        }
        """
        let variables: [String: Any] = ["conversationId": conversationId]
        struct Payload: Decodable { let unarchiveConversation: Result?; struct Result: Decodable { let message: String? } }
        _ = try await client.execute(query: mutation, variables: variables, responseType: Payload.self)
    }
    
    /// Delete all conversations (admin/self-service). Matches Flutter deleteAllConversations.
    func deleteAllConversations() async throws -> (success: Bool, message: String?, deletedConversationsCount: Int?, deletedOrdersCount: Int?) {
        let mutation = """
        mutation DeleteAllConversations {
          deleteAllConversations {
            success
            message
            deletedConversationsCount
            deletedOrdersCount
          }
        }
        """
        struct Payload: Decodable {
            let deleteAllConversations: Result?
            struct Result: Decodable {
                let success: Bool?
                let message: String?
                let deletedConversationsCount: Int?
                let deletedOrdersCount: Int?
            }
        }
        let response: Payload = try await client.execute(query: mutation, variables: [:], responseType: Payload.self)
        let result = response.deleteAllConversations
        return (result?.success ?? false, result?.message, result?.deletedConversationsCount, result?.deletedOrdersCount)
    }
    
    private func parseDate(_ dateString: String?) -> Date? { parseGraphQLDateString(dateString) }
}

/// One product line on a conversation-linked order (multi-buy uses several).
struct ConversationOrderLineSummary: Hashable, Identifiable {
    var id: String { productId }
    let productId: String
    let name: String
    let imageUrl: String?
    let price: Double?
}

/// Minimal order info for a conversation (sale confirmation).
struct ConversationOrder: Hashable {
    let id: String
    /// Human-readable order ref when the API provides it (same as `Order.publicId`).
    let publicId: String?
    let status: String
    let total: Double
    let firstProductName: String?
    let firstProductImageUrl: String?
    /// First product id for navigation to product detail.
    let firstProductId: String?
    /// Order creation time; used for list preview when there is no last message time.
    let createdAt: Date?
    /// All products on this order (same seller multi-buy = one order, multiple lines).
    let lineItems: [ConversationOrderLineSummary]

    var isMultibuy: Bool { lineItems.count > 1 }
}

struct Conversation: Hashable {
    let id: String
    let recipient: User
    let lastMessage: String?
    /// Username of the message sender for `lastMessage` (useful for role-specific UI like seller sale text).
    let lastMessageSenderUsername: String?
    let lastMessageTime: Date?
    let unreadCount: Int
    let offer: OfferInfo?
    let order: ConversationOrder?
    /// Full offer negotiation thread from `conversationById.offerHistory` (server source of truth). Nil when not loaded (e.g. inbox list).
    let offerHistory: [OfferInfo]?

    init(
        id: String,
        recipient: User,
        lastMessage: String?,
        lastMessageSenderUsername: String? = nil,
        lastMessageTime: Date?,
        unreadCount: Int,
        offer: OfferInfo? = nil,
        order: ConversationOrder? = nil,
        offerHistory: [OfferInfo]? = nil
    ) {
        self.id = id
        self.recipient = recipient
        self.lastMessage = lastMessage
        self.lastMessageSenderUsername = lastMessageSenderUsername
        self.lastMessageTime = lastMessageTime
        self.unreadCount = unreadCount
        self.offer = offer
        self.order = order
        self.offerHistory = offerHistory
    }

    static func idString(from anyCodable: AnyCodable?) -> String? {
        guard let ac = anyCodable else { return nil }
        if let i = ac.value as? Int { return String(i) }
        if let s = ac.value as? String { return s }
        return String(describing: ac.value)
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }

    static func offerInfo(from data: OfferData) -> OfferInfo? {
        let idStr = idString(from: data.id) ?? ""
        guard !idStr.isEmpty else { return nil }
        let price: Double = data.offerPrice?.value ?? 0
        // Prefer createdBy (sender of this offer/counter) for display so "X offered" is correct.
        let displayUsername = data.createdBy ?? data.buyer?.username
        let financialBuyer: String? = {
            let t = data.buyer?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }()
        let buyer: OfferInfo.OfferUser? = displayUsername.map { OfferInfo.OfferUser(username: $0, profilePictureUrl: data.buyer?.profilePictureUrl) }
        let products: [OfferInfo.OfferProduct]? = data.products?.map { p in
            OfferInfo.OfferProduct(
                id: idString(from: p.id),
                name: p.name,
                seller: p.seller.map { OfferInfo.OfferUser(username: $0.username, profilePictureUrl: $0.profilePictureUrl) }
            )
        }
        return OfferInfo(
            id: idStr,
            backendId: idStr,
            status: data.status,
            offerPrice: price,
            buyer: buyer,
            products: products,
            createdAt: parseGraphQLDateString(data.createdAt),
            sentByCurrentUser: false,
            financialBuyerUsername: financialBuyer,
            updatedByUsername: data.updatedBy
        )
    }
}

struct ConversationsResponse: Decodable {
    let conversations: [ConversationData]?
}

struct ArchivedConversationsResponse: Decodable {
    let archivedConversations: [ConversationData]?
}

struct ConversationData: Decodable {
    let id: AnyCodable?
    let recipient: UserData?
    let lastMessage: MessageData?
    let unreadMessagesCount: Int?
    let offer: OfferData?
    let order: ConversationOrderData?
    let offerHistory: [OfferData]?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(AnyCodable.self, forKey: .id)
        recipient = try c.decodeIfPresent(UserData.self, forKey: .recipient)
        lastMessage = try? c.decode(MessageData.self, forKey: .lastMessage)
        unreadMessagesCount = try c.decodeIfPresent(Int.self, forKey: .unreadMessagesCount)
        offer = try? c.decode(OfferData.self, forKey: .offer)
        order = try? c.decode(ConversationOrderData.self, forKey: .order)
        offerHistory = try? c.decode([OfferData].self, forKey: .offerHistory)
    }
    private enum CodingKeys: String, CodingKey { case id, recipient, lastMessage, unreadMessagesCount, offer, order, offerHistory }
}

/// Order summary on a conversation (from conversations query).
struct ConversationOrderData: Decodable {
    let id: AnyCodable?
    let publicId: String?
    let status: String?
    let createdAt: String?
    let products: [ConversationOrderProductData]?
    /// Decoded leniently (Int/String/Double) so order is not dropped when backend type differs.
    private let priceTotalValue: Double?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(AnyCodable.self, forKey: .id)).flatMap { $0 }
        publicId = try? c.decodeIfPresent(String.self, forKey: .publicId)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)).flatMap { $0 }
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        priceTotalValue = (try? c.decode(PriceTotalCodable.self, forKey: .priceTotal))?.value
            ?? (try? c.decode(AnyCodable.self, forKey: .priceTotal)).flatMap { ac in
                let v = ac.value
                if let d = v as? Double { return d }
                if let i = v as? Int { return Double(i) }
                if let s = v as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
                return nil
            }
        products = try? c.decode([ConversationOrderProductData].self, forKey: .products)
    }
    private enum CodingKeys: String, CodingKey { case id, publicId, status, priceTotal, createdAt, products }
    struct ConversationOrderProductData: Decodable {
        let id: AnyCodable?
        let name: String?
        /// Backend may send [String] or [{"url": "..."}]; decode leniently and expose first URL.
        private let imagesUrlElements: [OrderImageUrlElement]?
        private let priceFlexible: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decodeIfPresent(AnyCodable.self, forKey: .id)
            name = try c.decodeIfPresent(String.self, forKey: .name)
            imagesUrlElements = try? c.decode([OrderImageUrlElement].self, forKey: .imagesUrl)
            if let d = try? c.decode(Double.self, forKey: .price) {
                priceFlexible = d
            } else if let i = try? c.decode(Int.self, forKey: .price) {
                priceFlexible = Double(i)
            } else if let s = try? c.decode(String.self, forKey: .price) {
                priceFlexible = Double(s.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                priceFlexible = nil
            }
        }
        private enum CodingKeys: String, CodingKey { case id, name, imagesUrl, price }
        /// First image URL whether backend sent strings or objects with "url".
        var firstImageUrl: String? { imagesUrlElements?.first?.urlString }
        var unitPrice: Double? { priceFlexible }
    }
    /// Decodes "url" string or object { "url": "..." } from product imagesUrl array.
    /// Backend may send array of JSON strings like ["{\"url\":\"https://...\"}"], so parse that to extract url.
    private struct OrderImageUrlElement: Decodable {
        let urlString: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) {
                urlString = ProductListImageURL.preferredString(from: s)
                return
            }
            if let dict = try? c.decode([String: String].self) {
                urlString = ProductListImageURL.preferredString(fromStringKeyedJSON: dict)
                return
            }
            urlString = nil
        }
    }
    var priceTotalDouble: Double { priceTotalValue ?? 0 }
}

/// Decodes priceTotal when backend sends Double (AnyCodable only supports Int/String).
private struct PriceTotalCodable: Decodable {
    let value: Double
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { value = d; return }
        if let i = try? c.decode(Int.self) { value = Double(i); return }
        if let s = try? c.decode(String.self) { value = Double(s.trimmingCharacters(in: .whitespaces)) ?? 0; return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected number or string for priceTotal")
    }
}

struct OfferData: Decodable {
    let id: AnyCodable?
    let status: String?
    fileprivate let offerPrice: OfferPriceValue?
    /// Username of who sent this offer (created_by); use for "X offered" when present so counters show correct sender.
    let createdBy: String?
    /// Username of who last updated status (e.g. accepted); GraphQL `updatedBy`.
    let updatedBy: String?
    let buyer: OfferUserData?
    let products: [OfferProductData]?
    let createdAt: String?
    struct OfferUserData: Decodable {
        let username: String?
        let profilePictureUrl: String?
    }
    struct OfferProductData: Decodable {
        let id: AnyCodable?
        let name: String?
        let seller: OfferUserData?
    }
}

/// Accepts Double, Decimal, or String for offerPrice (backend may return any).
fileprivate enum OfferPriceValue: Decodable {
    case double(Double)
    case decimal(Decimal)
    case string(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let dec = try? c.decode(Decimal.self) { self = .decimal(dec); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Double, Decimal, or String")
    }
    var value: Double {
        switch self {
        case .double(let d): return d
        case .decimal(let d): return NSDecimalNumber(decimal: d).doubleValue
        case .string(let s): return Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
        }
    }
}

fileprivate enum DoubleOrDecimal: Decodable {
    case double(Double)
    case decimal(Decimal)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let dec = try? c.decode(Decimal.self) { self = .decimal(dec); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected Double or Decimal")
    }
    var value: Double {
        switch self {
        case .double(let d): return d
        case .decimal(let d): return NSDecimalNumber(decimal: d).doubleValue
        }
    }
}

struct ConversationResponse: Decodable {
    let conversation: ConversationDetailData?
}

/// Response when conversation(id:) returns [MessageType] directly (not wrapped in { id, messages }).
struct ConversationMessagesResponse: Decodable {
    let conversation: [MessageData]?
}

struct ConversationDetailData: Decodable {
    let id: String?
    let messages: [MessageData]?
}

struct MessageData: Decodable {
    let id: AnyCodable?
    let text: String?
    let createdAt: String?
    let read: Bool?
    let sender: UserData?
    let isItem: Bool?
    let itemId: Int?
    let itemType: String?
}

struct UserData: Decodable {
    let id: AnyCodable?
    let username: String?
    let displayName: String?
    let profilePictureUrl: String?
}

struct CreateChatResponse: Decodable {
    let createChat: CreateChatData?
}

struct CreateChatData: Decodable {
    let chat: ChatData?
}

struct ChatData: Decodable {
    let id: AnyCodable?
    let recipient: UserData?
}

struct SendMessageResponse: Decodable {
    let sendMessage: SendMessagePayload?
}

struct SendMessagePayload: Decodable {
    let success: Bool?
    let messageId: Int?
}

// AnyCodable is defined in UserService.swift - reuse it

enum ChatError: Error, LocalizedError {
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        }
    }
}
