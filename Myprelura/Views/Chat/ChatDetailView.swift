import SwiftUI
import Combine

/// Holds peer typing state updated from WebSocket callbacks. Using `ObservableObject` avoids mutating `@State` from
/// closures that capture `ChatDetailView` by value, which can fail to refresh the typing row.
@MainActor
private final class ChatRemoteTypingIndicatorModel: ObservableObject {
    @Published var isPeerTyping = false
    @Published var peerUsername: String?
    private var autoHideTask: Task<Void, Never>?

    func handleSocketEvent(_ event: TypingSocketEvent, currentUsername: String?) {
        let sender = event.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let me = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if !sender.isEmpty, !me.isEmpty, sender.lowercased() == me { return }

        peerUsername = sender.isEmpty ? nil : sender
        autoHideTask?.cancel()
        if event.isTyping {
            isPeerTyping = true
            autoHideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    self?.isPeerTyping = false
                }
            }
        } else {
            isPeerTyping = false
        }
    }

    func clear() {
        autoHideTask?.cancel()
        autoHideTask = nil
        isPeerTyping = false
        peerUsername = nil
    }
}

/// Forwards WebSocket payloads into SwiftUI. Inbound chat rows bump `@Published chatInboundSequence` so `onChange`
/// runs reliably; `PassthroughSubject` + `onReceive` for chat did not consistently refresh bubbles.
/// Socket closures must not capture `ChatDetailView` with `[self]` (a struct).
@MainActor
private final class ChatWebSocketUIBridge: ObservableObject {
    private var chatInboundQueue: [(Message, String?)] = []
    @Published private(set) var chatInboundSequence: UInt64 = 0

    let offerChannel = PassthroughSubject<OfferSocketEvent, Never>()
    let orderChannel = PassthroughSubject<OrderSocketEvent, Never>()
    let reactionChannel = PassthroughSubject<MessageReactionSocketEvent, Never>()

    func emitIncomingMessage(_ msg: Message, _ echoUuid: String?, conversationId: String) {
        chatInboundQueue.append((msg, echoUuid))
        chatInboundSequence &+= 1
        ChatThreadUIUpdateDebugState.shared.recordBridgeEmit(
            conversationId: conversationId,
            sequence: chatInboundSequence,
            queueDepthAfterAppend: chatInboundQueue.count
        )
    }

    func drainInboundChatMessages() -> [(Message, String?)] {
        defer { chatInboundQueue.removeAll() }
        return chatInboundQueue
    }

    func emitOffer(_ event: OfferSocketEvent) {
        offerChannel.send(event)
    }

    func emitOrder(_ event: OrderSocketEvent) {
        orderChannel.send(event)
    }

    func emitReaction(_ event: MessageReactionSocketEvent) {
        reactionChannel.send(event)
    }
}

/// Persists the last-known product image URL for chat headers so thumbnails do not show an endless spinner after leaving the thread.
fileprivate enum ChatHeaderProductImageURLStore {
    private static let prefix = "chatHeaderImg_"

    static func persist(productId: Int, url: String?) {
        let key = prefix + String(productId)
        if let u = url?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            UserDefaults.standard.set(u, forKey: key)
        }
    }

    static func url(forProductId productId: Int) -> String? {
        UserDefaults.standard.string(forKey: prefix + String(productId))
    }
}

/// Resolves conversation with seller (existing or new) then shows ChatDetailView. Used when tapping message icon on product detail.
/// When opened from product detail, pass `item` so the chat shows the product at the top (Flutter behavior).
struct ChatWithSellerView: View {
    let seller: User
    /// When non-nil, chat shows this product at the top (e.g. when starting conversation from product detail).
    var item: Item? = nil
    let authService: AuthService?
    @State private var resolvedConversation: Conversation?
    @State private var isLoading = true
    @StateObject private var chatService = ChatService()

    var body: some View {
        Group {
            if let conv = resolvedConversation {
                ChatDetailView(conversation: conv, item: item)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
            } else {
                ChatDetailView(conversation: Conversation(id: "0", recipient: seller, lastMessage: nil, lastMessageTime: nil, unreadCount: 0), item: item)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let token = authService?.authToken {
                chatService.updateAuthToken(token)
            }
            Task {
                await resolveConversation()
            }
        }
    }

    private func resolveConversation() async {
        do {
            let convs = try await chatService.getConversations()
            let existing: Conversation? = {
                guard let productId = item?.productId, !productId.isEmpty else {
                    return convs.first { $0.recipient.username == seller.username }
                }
                let sameSeller = convs.filter { $0.recipient.username == seller.username }
                // Product-scoped reuse: only reuse when the thread is already tied to this product.
                if let offerMatch = sameSeller.first(where: {
                    $0.offer?.products?.contains(where: { $0.id == productId }) == true
                }) {
                    return offerMatch
                }
                if let orderMatch = sameSeller.first(where: { $0.order?.firstProductId == productId }) {
                    return orderMatch
                }
                return nil
            }()
            if let conv = existing {
                await MainActor.run {
                    resolvedConversation = conv
                    isLoading = false
                }
                return
            }
            let newConv = try await chatService.createChat(recipient: seller.username)
            await MainActor.run {
                resolvedConversation = newConv
                isLoading = false
            }
        } catch {
            await MainActor.run {
                resolvedConversation = Conversation(id: "0", recipient: seller, lastMessage: nil, lastMessageTime: nil, unreadCount: 0)
                isLoading = false
            }
        }
    }
}

/// One item in the chat timeline: message, offer card, or sold event. Sorted by time.
private struct ChatFolderActionError: Identifiable {
    let id: UUID
    let title: String
    let message: String

    init(title: String, message: String) {
        self.id = UUID()
        self.title = title
        self.message = message
    }
}

/// Tighter horizontal inset for the chat thread, headers, composer, and product card (half of former `md` padding).
fileprivate enum ChatThreadLayout {
    static let horizontalGutter: CGFloat = Theme.Spacing.md / 2
}

enum ChatItem: Hashable {
    case message(UUID)
    case offer(String)
    case sold(OrderInfo)
    case soldBanner(Date)

    var id: String {
        switch self {
        case .message(let m): return "msg-\(m.uuidString)"
        case .offer(let o): return "offer-\(o)"
        case .sold(let o): return "sold-\(o.id)"
        case .soldBanner(let d): return "sold-banner-\(Int(d.timeIntervalSince1970))"
        }
    }

    var isOffer: Bool {
        if case .offer = self { return true }
        return false
    }
    var isSold: Bool {
        if case .sold = self { return true }
        return false
    }
    var isSoldBanner: Bool {
        if case .soldBanner = self { return true }
        return false
    }
}

struct ChatDetailView: View {
    let conversation: Conversation
    /// When non-nil, show this product at the top of the chat (Flutter: productId → ProductCard at top).
    var item: Item? = nil
    /// When true, the thread was opened from the archived inbox list (⋯ menu shows Restore instead of Archive).
    var isOpenedFromArchive: Bool = false

    @EnvironmentObject var authService: AuthService
    @Environment(\.optionalTabCoordinator) private var tabCoordinator
    @Environment(\.dismiss) private var dismiss
    /// When the app backgrounds, drop the chat WebSocket so the server clears `chat_<id>` presence; otherwise FCM is skipped while the cache says the user is still “in the room.”
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var chatService = ChatService()
    @State private var displayedConversation: Conversation
    @State private var messages: [Message] = []
    @State private var newMessage: String = ""
    @FocusState private var isMessageFieldFocused: Bool
    @State private var isLoading: Bool = false
    @State private var webSocket: ChatWebSocketService?
    @StateObject private var remoteTypingIndicator = ChatRemoteTypingIndicatorModel()
    @StateObject private var socketUIBridge = ChatWebSocketUIBridge()
    /// Periodically re-sends typing while the composer is non-empty so the peer’s indicator does not expire mid-sentence.
    @State private var typingKeepaliveTask: Task<Void, Never>?
    @State private var didSendTypingStart = false
    @State private var pendingMessageUUID: String?
    @State private var showCounterOfferSheet = false
    /// The specific offer card the user tapped to open the counter sheet.
    @State private var counterTargetOffer: OfferInfo?
    @State private var isRespondingToOffer = false
    @State private var offerError: String?
    /// Persisted per thread (UserDefaults): listing is no longer actionable (sold / inactive).
    @State private var showItemSoldBanner = false
    @State private var offerModalSubmitting = false
    @State private var showReportUserSheet = false
    @State private var folderActionError: ChatFolderActionError?
    @State private var reconnectTask: Task<Void, Never>?
    @State private var reconnectAttempt = 0
    /// Debounced GraphQL reload after socket-delivered rows (order/cancellation paths already refetch; this mirrors that for plain text).
    @State private var chatCatchUpFromServerTask: Task<Void, Never>?
    /// WhatsApp-style long-press reactions (local persistence per device).
    @ObservedObject private var messageReactionsStore = ChatMessageReactionsStore.shared
    /// Learns which reaction emojis you use so the long-press bar surfaces them first.
    @ObservedObject private var chatReactionEmojiUsageStore = ChatReactionEmojiUsageStore.shared
    @State private var reactionOverlayMessage: Message?
    @State private var reactionBubbleFrames: [UUID: CGRect] = [:]
    @State private var showExtendedReactionEmojis = false
    /// Per-message timestamp visibility: key present means user override; value is shown/hidden (default comes from grouping when absent).
    @State private var timestampVisibilityOverrides: [UUID: Bool] = [:]
    private struct PayNowPayload: Identifiable {
        let id = UUID()
        let products: [Item]
        let totalPrice: Double
    }
    @State private var payNowPayload: PayNowPayload?
    /// Fetched product for offer-conversation header (thumbnail + price bar). Cached by product id so we don't refetch.
    @State private var offerProductItem: Item?
    private static var offerProductCache: [Int: Item] = [:]
    /// Fetched product for order-conversation header (sale confirmation bar); enables tap-to-open product. Cached by product id.
    @State private var orderProductItem: Item?
    private static var orderProductCache: [Int: Item] = [:]
    /// Single source of truth for offer cards. UI = source of truth; server used only to seed on load or confirm after send.
    @State private var offers: [OfferInfo] = []
    /// Synthetic "accepted snapshot" suffix used to duplicate an accepted card so it never turns red/declined later.
    private static let acceptedSnapshotBackendIdSuffix = "-accepted-snapshot"
    /// After `getConversationById` completes for this open; until then we avoid seeding from a single inbox `offer` (prevents one-card → full-history flash).
    @State private var hasFinishedInitialConversationFetch = false
    /// Shown when we’re waiting on server `offerHistory` and have no local cache.
    @State private var isLoadingOfferHistory = false
    /// Prevent repeated initial scroll bursts when re-entering the same thread.
    @State private var hasAutoScrolledToBottomForThisChat = false
    /// Stable id at end of scroll content so `scrollTo` works with `LazyVStack` (last message id may not be laid out yet).
    private static let chatBottomAnchorId = "chat_bottom_anchor"
    private static let chatPeerTypingScrollId = "chat_peer_typing_inline"

    private let productService = ProductService()
    private let orderCancellationUserService = UserService()

    /// Cache for re-open: restore offers when returning to chat (API only returns latest).
    private static var offerHistoryCache: [String: [OfferInfo]] = [:]
    private static let offerHistoryUserDefaultsPrefix = "offerHistory_"
    /// Order of items in the chat (message / offer / sold), sorted by date.
    @State private var timelineOrder: [ChatItem] = []
    private static var timelineOrderCache: [String: [ChatItem]] = [:]
    /// In-memory + disk cache for thread messages (same key scheme as offer history).
    private static var messagesMemoryCache: [String: [Message]] = [:]
    private static let messagesUserDefaultsPrefix = "chatMessages_"

    /// Cache key per conversation and current user so switching accounts doesn't show wrong sender.
    private func offerCacheKey(convId: String) -> String {
        "\(convId)_\(authService.username ?? "")"
    }

    private static let itemSoldBannerUserDefaultsPrefix = "chatItemSoldBanner_"

    private func itemSoldBannerStorageKey() -> String {
        Self.itemSoldBannerUserDefaultsPrefix + offerCacheKey(convId: displayedConversation.id)
    }

    private func loadItemSoldBannerFromPersist() {
        showItemSoldBanner = UserDefaults.standard.bool(forKey: itemSoldBannerStorageKey())
    }

    private func setItemSoldBannerVisible(_ visible: Bool) {
        showItemSoldBanner = visible
        UserDefaults.standard.set(visible, forKey: itemSoldBannerStorageKey())
    }

    /// Backend: inactive products / sold listings when creating or countering an offer.
    private func isOfferProductUnavailableMessage(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.contains("the following products are not available") { return true }
        if t.contains("this product is not available") { return true }
        if t.contains("not available") && t.contains("product") { return true }
        return false
    }

    private func refreshItemSoldBannerFromProductState() {
        if displayedConversation.order != nil || messages.contains(where: { $0.isSoldConfirmation }) {
            if showItemSoldBanner { setItemSoldBannerVisible(false) }
            return
        }
        if let it = item, it.status.uppercased() == "SOLD" {
            setItemSoldBannerVisible(true)
            return
        }
        if let p = offerProductItem, p.status.uppercased() != "ACTIVE" {
            setItemSoldBannerVisible(true)
        }
    }

    private static func persistOfferHistory(key: String, offers: [OfferInfo]) {
        guard let data = try? JSONEncoder().encode(offers) else { return }
        UserDefaults.standard.set(data, forKey: offerHistoryUserDefaultsPrefix + key)
    }

    private static func loadOfferHistory(key: String) -> [OfferInfo]? {
        guard let data = UserDefaults.standard.data(forKey: offerHistoryUserDefaultsPrefix + key),
              let offers = try? JSONDecoder().decode([OfferInfo].self, from: data) else { return nil }
        return offers
    }

    private static func persistMessagesCache(key: String, messages: [Message]) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        guard let data = try? enc.encode(messages) else { return }
        UserDefaults.standard.set(data, forKey: messagesUserDefaultsPrefix + key)
    }

    private static func loadMessagesCache(key: String) -> [Message]? {
        guard let data = UserDefaults.standard.data(forKey: messagesUserDefaultsPrefix + key) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode([Message].self, from: data)
    }

    /// Restore messages from memory or disk before network fetch so back navigation and cold relaunch don’t flash an empty thread.
    private func restoreCachedMessagesBeforeLoad() {
        let convId = displayedConversation.id
        guard convId != "0" else { return }
        let key = offerCacheKey(convId: convId)
        if let mem = Self.messagesMemoryCache[key], !mem.isEmpty {
            messages = mem
            return
        }
        if let disk = Self.loadMessagesCache(key: key), !disk.isEmpty {
            messages = disk
            Self.messagesMemoryCache[key] = disk
        }
    }

    private func cacheMessagesForConversation(_ msgs: [Message], convId: String) {
        guard convId != "0" else { return }
        let key = offerCacheKey(convId: convId)
        Self.messagesMemoryCache[key] = msgs
        Self.persistMessagesCache(key: key, messages: msgs)
    }

    /// Merge API messages with any local-only rows (typically optimistic sends without `backendId`) so a refetch cannot wipe text that the server has not returned yet.
    /// Also keep WebSocket-delivered rows that already have a `backendId` but are missing from this server snapshot (GET can lag behind the room broadcast).
    private func mergedThreadMessages(server: [Message], local: [Message]) -> [Message] {
        if server.isEmpty {
            return local.sorted { $0.timestamp < $1.timestamp }
        }
        var result = server
        let serverIds = Set(server.map(\.id))
        let serverBackendIds = Set(server.compactMap(\.backendId))
        for localMsg in local {
            if let bid = localMsg.backendId {
                if !serverBackendIds.contains(bid), !serverIds.contains(localMsg.id) {
                    result.append(localMsg)
                }
                continue
            }
            if !isCurrentUser(username: localMsg.senderUsername) {
                if localMsg.isOfferContent || localMsg.isSoldConfirmation || localMsg.isOrderIssue
                    || localMsg.isOrderCancellationRequest || localMsg.isOrderCancellationOutcome { continue }
                let trimmedPeer = localMsg.content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedPeer.isEmpty else { continue }
                if serverIds.contains(localMsg.id) { continue }
                let peerDup = server.contains { s in
                    s.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmedPeer
                        && abs(s.timestamp.timeIntervalSince(localMsg.timestamp)) < 180
                }
                if !peerDup { result.append(localMsg) }
                continue
            }
            if localMsg.isOfferContent || localMsg.isSoldConfirmation || localMsg.isOrderIssue
                || localMsg.isOrderCancellationRequest || localMsg.isOrderCancellationOutcome { continue }
            let trimmed = localMsg.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if serverIds.contains(localMsg.id) { continue }
            let duplicatedOnServer = server.contains { s in
                s.content.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed
                    && abs(s.timestamp.timeIntervalSince(localMsg.timestamp)) < 180
            }
            if duplicatedOnServer { continue }
            result.append(localMsg)
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    /// Latest row suitable for inbox subtitle (skip offer / sold / issue payloads at the tail of the thread).
    private func lastPlainChatMessageForInboxPreview() -> Message? {
        for m in messages.reversed() {
            if m.isOfferContent || m.isSoldConfirmation || m.isOrderIssue
                || m.isOrderCancellationRequest || m.isOrderCancellationOutcome { continue }
            if m.type == "item" || m.type == "sold_confirmation" { continue }
            return m
        }
        return messages.last
    }

    private func hasLocalOfferHistoryCache(convId: String) -> Bool {
        let key = offerCacheKey(convId: convId)
        if let c = Self.offerHistoryCache[key], !c.isEmpty { return true }
        if let p = Self.loadOfferHistory(key: key), !p.isEmpty { return true }
        return false
    }

    /// Reset fetch gate + loader when opening or switching chats (placeholder id `"0"` skips deferral).
    private func refreshOfferHistoryLoadingFlagsForCurrentConversation() {
        let convId = displayedConversation.id
        if convId == "0" {
            hasFinishedInitialConversationFetch = true
            isLoadingOfferHistory = false
            return
        }
        hasFinishedInitialConversationFetch = false
        isLoadingOfferHistory =
            displayedConversation.offer != nil
            && displayedConversation.offerHistory == nil
            && !hasLocalOfferHistoryCache(convId: convId)
    }

    init(conversation: Conversation, item: Item? = nil, isOpenedFromArchive: Bool = false) {
        self.conversation = conversation
        self.item = item
        self.isOpenedFromArchive = isOpenedFromArchive
        _displayedConversation = State(initialValue: conversation)
        // Hydrate from in-memory product cache immediately so the header URL exists on first layout (onAppear ran too late → spinner).
        if let pid = conversation.offer?.products?.first?.id.flatMap({ Int($0) }) {
            _offerProductItem = State(initialValue: Self.offerProductCache[pid])
        } else {
            _offerProductItem = State(initialValue: nil)
        }
        if let oid = conversation.order?.firstProductId.flatMap({ Int($0) }) {
            _orderProductItem = State(initialValue: Self.orderProductCache[oid])
        } else {
            _orderProductItem = State(initialValue: nil)
        }
    }

    private var recipientTitle: String {
        PreluraSupportBranding.displayTitle(forRecipientUsername: displayedConversation.recipient.username)
    }

    private var typingDisplayName: String {
        let trimmed = remoteTypingIndicator.peerUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let raw = trimmed.isEmpty ? displayedConversation.recipient.username : trimmed
        return PreluraSupportBranding.displayTitle(forRecipientUsername: raw)
    }

    private var isSupportConversation: Bool {
        PreluraSupportBranding.isSupportRecipient(username: displayedConversation.recipient.username)
    }

    /// Messages to show: in offer conversations hide raw offer payload bubbles (offer card represents the offer).
    /// Hide sold_confirmation message bubbles (order is shown by OrderConfirmationCardView banner only).
    /// Collapse duplicate `order_issue` payloads (same issue id / public id / identical JSON) so support threads don’t show twin report cards.
    private var displayedMessages: [Message] {
        var list = messages.filter { !$0.isSoldConfirmation }
        if displayedConversation.offer != nil {
            list = list.filter { !$0.isOfferContent }
        }
        return Self.dedupeOrderIssueMessagesPreservingOrder(list)
    }

    /// One visible card per logical order-issue report (backend or client may persist the same context twice).
    private static func dedupeOrderIssueMessagesPreservingOrder(_ messages: [Message]) -> [Message] {
        var seen = Set<String>()
        return messages.filter { m in
            guard m.isOrderIssue else { return true }
            let key = orderIssueDedupeKey(m)
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private static func orderIssueDedupeKey(_ m: Message) -> String {
        if let d = m.parsedOrderIssueDetails {
            if let iid = d.issueId { return "iid:\(iid)" }
            let pid = d.publicId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !pid.isEmpty { return "pid:\(pid)" }
        }
        let trimmed = m.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return "raw:\(trimmed)"
    }

    private var isSeller: Bool {
        isCurrentUser(username: displayedConversation.offer?.products?.first?.seller?.username)
    }

    /// Seller role fallback for order-detail navigation when offer context is missing.
    private var isSellerForOrderDetail: Bool {
        if let soldEntry = timelineOrder.first(where: {
            if case .sold = $0 { return true }
            return false
        }), case let .sold(orderInfo) = soldEntry, orderInfo.rolesConfirmed {
            return isCurrentUser(username: orderInfo.sellerUsername)
        }
        return isSeller
    }

    /// Shown inside the message `ScrollView` above the bottom anchor so it scrolls with the thread and never sits on top of bubbles (typing in `safeAreaInset` overlapped the last rows).
    private var peerTypingRowInScrollContent: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            Text("\(typingDisplayName) is typing")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            TypingDotsView()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.xs)
        .padding(.bottom, Theme.Spacing.sm)
        .transition(.opacity)
    }

    private var messageInputBar: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .bottom, spacing: Theme.Spacing.sm) {
                TextField("Type a message...", text: $newMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($isMessageFieldFocused)
                    .lineLimit(1...10)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, ChatThreadLayout.horizontalGutter)
                    .padding(.vertical, 10)
                    .frame(minHeight: 44, alignment: .leading)
                    .background(Theme.Colors.secondaryBackground)
                    .cornerRadius(22)
                    .overlay(
                        RoundedRectangle(cornerRadius: 22)
                            .stroke(isMessageFieldFocused ? Theme.primaryColor : Theme.Colors.glassBorder, lineWidth: isMessageFieldFocused ? 2 : 1)
                    )
                    .foregroundColor(Theme.Colors.primaryText)
                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.Colors.secondaryText : Theme.primaryColor)
                }
                .disabled(newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
        }
        .padding(.horizontal, ChatThreadLayout.horizontalGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }

    // Payment sheet is presented via `fullScreenCover(item:)` for atomic payload updates.

    /// True when this message is from the other user and is the first in a run (show avatar). Also show avatar after a sold-confirmation banner.
    private func showAvatarForMessage(at index: Int) -> Bool {
        let list = displayedMessages
        guard index < list.count else { return false }
        let msg = list[index]
        let isOther = !isCurrentUser(username: msg.senderUsername)
        guard isOther else { return false }
        if index == 0 { return true }
        let prev = list[index - 1]
        if prev.isSoldConfirmation { return true }
        return isCurrentUser(username: prev.senderUsername)
    }

    /// Default: show timestamp only on the last bubble of a run (same sender, within 60s); hidden on earlier bubbles in the group.
    private func showTimestampForMessage(at index: Int) -> Bool {
        let list = displayedMessages
        guard index < list.count else { return true }
        if index == list.count - 1 { return true }
        let msg = list[index]
        let next = list[index + 1]
        if next.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            != msg.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() { return true }
        if next.timestamp.timeIntervalSince(msg.timestamp) > 60 { return true }
        return false
    }

    private func effectiveShowTimestamp(at index: Int, message: Message) -> Bool {
        if let override = timestampVisibilityOverrides[message.id] { return override }
        return showTimestampForMessage(at: index)
    }

    private func toggleTimestampVisibility(at index: Int, message: Message) {
        let cur = effectiveShowTimestamp(at: index, message: message)
        timestampVisibilityOverrides[message.id] = !cur
    }

    /// True when the previous timeline entry is a message from the same sender within 60 seconds (same group) — use for tight spacing.
    private func isSameGroupAsPrevious(timelineIndex: Int, message: Message) -> Bool {
        guard timelineIndex > 0, timelineIndex - 1 < timelineOrder.count else { return false }
        guard case .message(let prevId) = timelineOrder[timelineIndex - 1],
              let prev = displayedMessages.first(where: { $0.id == prevId }) else { return false }
        guard prev.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            == message.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else { return false }
        return message.timestamp.timeIntervalSince(prev.timestamp) <= 60
    }

    private static let chatAvatarSize: CGFloat = 32

    private var isSold: Bool {
        timelineOrder.contains { $0.isSold }
    }

    private func scrollToLatest(with proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(Self.chatBottomAnchorId, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } else {
            action()
        }
    }

    /// `LazyVStack` often has not materialized the last row on first layout; retry so open-thread lands at the bottom.
    private func scheduleScrollToBottom(proxy: ScrollViewProxy, delays: [TimeInterval], animated: Bool) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                scrollToLatest(with: proxy, animated: animated)
            }
        }
    }

    @ViewBuilder
    private func timelineRow(timelineIndex: Int, entry: ChatItem) -> some View {
        switch entry {
        case .message(let messageId):
            if let index = displayedMessages.firstIndex(where: { $0.id == messageId }),
               index < displayedMessages.count {
                let message = displayedMessages[index]
                let topPadding: CGFloat = timelineIndex == 0 ? 0 : (isSameGroupAsPrevious(timelineIndex: timelineIndex, message: message) ? Theme.Spacing.xs : Theme.Spacing.md)
                if message.isOrderCancellationRequest, let cancelPayload = message.parsedOrderCancellationRequestPayload {
                    let outcomeLater = displayedMessages.dropFirst(index + 1).contains { later in
                        guard let o = later.parsedOrderCancellationOutcomePayload else { return false }
                        return o.orderId == cancelPayload.orderId
                    }
                    let cancelCard = OrderCancellationRequestChatCardView(
                        message: message,
                        payload: cancelPayload,
                        resolvedByLaterOutcome: outcomeLater,
                        currentUsername: authService.username,
                        isSellerRoleFallback: isSeller,
                        onFinished: { loadConversationAndMessagesFromBackend() }
                    )
                    .environmentObject(authService)
                    .id(message.id)
                    let topPadCancel: CGFloat = timelineIndex == 0 ? 0 : (isSameGroupAsPrevious(timelineIndex: timelineIndex, message: message) ? Theme.Spacing.xs : Theme.Spacing.md)
                    cancelCard
                        .padding(.top, topPadCancel)
                } else if message.isOrderCancellationOutcome {
                    let outcomeCard = OrderCancellationOutcomeChatCardView(message: message)
                        .id(message.id)
                    let topPadOut: CGFloat = timelineIndex == 0 ? 0 : (isSameGroupAsPrevious(timelineIndex: timelineIndex, message: message) ? Theme.Spacing.xs : Theme.Spacing.md)
                    outcomeCard
                        .padding(.top, topPadOut)
                } else if message.isOrderIssue {
                    let issueCard = OrderIssueChatCardView(
                        message: message,
                        currentUsername: authService.username
                    )
                    .id(message.id)
                    if isCurrentUser(username: message.senderUsername) {
                        issueCard
                            .padding(.leading, Theme.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, topPadding)
                    } else {
                        HStack(alignment: .top, spacing: 4) {
                            chatTitleAvatar(url: displayedConversation.recipient.avatarURL, username: displayedConversation.recipient.username)
                            issueCard
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, topPadding)
                    }
                } else {
                    let isCurrentUserMessage = isCurrentUser(username: message.senderUsername)
                    let showSeenLabel: Bool = {
                        guard isCurrentUserMessage, message.read else { return false }
                        guard let lastOwn = displayedMessages.lastIndex(where: { isCurrentUser(username: $0.senderUsername) }) else { return false }
                        return lastOwn == index
                    }()
                    let reactionKey = ChatMessageReactionsStore.stableKey(for: message)
                    let bubbleReactions = messageReactionsStore.reactionsByUsername(
                        conversationId: displayedConversation.id,
                        messageKey: reactionKey
                    )
                    MessageBubbleView(
                        message: message,
                        isCurrentUser: isCurrentUserMessage,
                        showAvatar: showAvatarForMessage(at: index),
                        showTimestamp: effectiveShowTimestamp(at: index, message: message),
                        avatarURL: showAvatarForMessage(at: index) ? displayedConversation.recipient.avatarURL : nil,
                        recipientUsername: displayedConversation.recipient.username,
                        showSeenLabel: showSeenLabel,
                        reactionsByUsername: bubbleReactions,
                        onLongPress: displayedConversation.id != "0"
                            ? {
                                reactionOverlayMessage = message
                            }
                            : nil,
                        onDoubleTapHeart: displayedConversation.id != "0"
                            ? {
                                applyChatReaction(message: message, emoji: ChatReactionEmojiUsageStore.doubleTapHeartEmoji)
                            }
                            : nil,
                        onToggleTimestampVisibility: displayedConversation.id != "0"
                            ? {
                                toggleTimestampVisibility(at: index, message: message)
                            }
                            : nil,
                        onTapMyReactionChip: displayedConversation.id != "0"
                            ? { removeChatReactionIfMine(message: message, emoji: $0) }
                            : nil,
                        currentUsernameForReactions: authService.username,
                        isReactionTargeted: reactionOverlayMessage?.id == message.id
                    )
                    .id(message.id)
                    .padding(.top, topPadding)
                }
            }
        case .offer(let offerId):
            if let offer = offers.first(where: { $0.id == offerId }) {
                let isLatest = offer.id == offers.last?.id
                let prevIsOffer = (timelineIndex > 0 && timelineIndex - 1 < timelineOrder.count) && (timelineOrder[timelineIndex - 1].isOffer)
                let topPadding: CGFloat = timelineIndex == 0 ? 0 : (prevIsOffer ? 0 : Theme.Spacing.md)
                let isOfferFromOther = isOfferFromOtherUser(offer)
                let cardContent = OfferCardView(
                    offer: offer,
                    currentUsername: authService.username,
                    isSeller: isSeller,
                    isResponding: isLatest ? isRespondingToOffer : false,
                    errorMessage: isLatest ? (showItemSoldBanner ? nil : offerError) : nil,
                    onAccept: { await handleRespondToOffer(action: "ACCEPT", targetOffer: offer) },
                    onDecline: { await handleRespondToOffer(action: "REJECT", targetOffer: offer) },
                    onSendNewOffer: { counterTargetOffer = offer; showCounterOfferSheet = true },
                    onPayNow: { presentPayNow(for: offer) },
                    forceGreyedOut: !isLatest || isSold
                )
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.background)
                .id(offer.id)
                Group {
                    if isOfferFromOther {
                        HStack(alignment: .top, spacing: 4) {
                            chatTitleAvatar(url: displayedConversation.recipient.avatarURL, username: displayedConversation.recipient.username)
                            cardContent
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        cardContent
                            .padding(.leading, Theme.Spacing.xs)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, topPadding)
            }
        case .sold(let orderInfo):
            let prevIsOfferOrSold = (timelineIndex > 0 && timelineIndex - 1 < timelineOrder.count) && (timelineOrder[timelineIndex - 1].isOffer || timelineOrder[timelineIndex - 1].isSold)
            let topPadding: CGFloat = timelineIndex == 0 ? 0 : (prevIsOfferOrSold ? 0 : Theme.Spacing.md)
            HStack(alignment: .top, spacing: 4) {
                chatTitleAvatar(
                    url: displayedConversation.recipient.avatarURL,
                    username: displayedConversation.recipient.username
                )
                .padding(.top, Theme.Spacing.md)
                SoldConfirmationCardView(
                    order: orderInfo,
                    currentUsername: authService.username,
                    conversationId: displayedConversation.id,
                    detailOrder: conversationOrderForDetail,
                    isSellerView: isSellerForOrderDetail,
                    onOrderChanged: {
                        Task { await refetchConversationForOrder() }
                    }
                )
                    .id("sold_\(orderInfo.id)")
                    .padding(.vertical, Theme.Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
        case .soldBanner:
            let prevIsOfferOrSold = (timelineIndex > 0 && timelineIndex - 1 < timelineOrder.count) && (timelineOrder[timelineIndex - 1].isOffer || timelineOrder[timelineIndex - 1].isSold || timelineOrder[timelineIndex - 1].isSoldBanner)
            let topPadding: CGFloat = timelineIndex == 0 ? 0 : (prevIsOfferOrSold ? 0 : Theme.Spacing.md)
            itemSoldPersistentBanner
                .padding(.top, topPadding)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if displayedConversation.order != nil {
                orderHeaderBar
                Rectangle()
                    .fill(Theme.Colors.glassBorder)
                    .frame(height: 0.5)
            } else if displayedConversation.offer != nil {
                offerProductHeaderBar
                Rectangle()
                    .fill(Theme.Colors.glassBorder)
                    .frame(height: 0.5)
            }
            if let item = item {
                ChatProductCardView(item: item)
                    .padding(.horizontal, ChatThreadLayout.horizontalGutter)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.background)
                if !offers.isEmpty {
                    Rectangle()
                        .fill(Theme.Colors.glassBorder)
                        .frame(height: 0.5)
                }
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if displayedConversation.id != "0",
                           !hasFinishedInitialConversationFetch,
                           messages.isEmpty,
                           timelineOrder.isEmpty {
                            VStack(spacing: Theme.Spacing.md) {
                                ProgressView()
                                Text("Loading messages…")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 120)
                        } else {
                            if isLoadingOfferHistory {
                                HStack(spacing: Theme.Spacing.sm) {
                                    Spacer(minLength: 0)
                                    ProgressView()
                                    Text("Loading")
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, Theme.Spacing.lg)
                                .frame(maxWidth: .infinity)
                            }
                            ForEach(Array(timelineOrder.enumerated()), id: \.1) { timelineIndex, entry in
                                timelineRow(timelineIndex: timelineIndex, entry: entry)
                            }
                        }
                        if remoteTypingIndicator.isPeerTyping {
                            peerTypingRowInScrollContent
                                .id(Self.chatPeerTypingScrollId)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id(Self.chatBottomAnchorId)
                    }
                    .padding(.horizontal, ChatThreadLayout.horizontalGutter)
                    .padding(.vertical, Theme.Spacing.sm)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard !hasAutoScrolledToBottomForThisChat else { return }
                    scheduleScrollToBottom(proxy: proxy, delays: [0, 0.05, 0.15, 0.35], animated: false)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) {
                        hasAutoScrolledToBottomForThisChat = true
                    }
                }
                .onChange(of: timelineOrder.count) { _, newCount in
                    guard newCount > 0 else { return }
                    scrollToLatest(with: proxy, animated: true)
                }
                .onChange(of: remoteTypingIndicator.isPeerTyping) { _, isTyping in
                    guard isTyping else { return }
                    scrollToLatest(with: proxy, animated: true)
                }
                .onChange(of: hasFinishedInitialConversationFetch) { _, done in
                    guard done else { return }
                    scheduleScrollToBottom(proxy: proxy, delays: [0, 0.08, 0.25], animated: false)
                }
                .onPreferenceChange(ChatBubbleFramePreferenceKey.self) { reactionBubbleFrames = $0 }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    messageInputBar
                }
            }
        }
        .overlay {
            if let msg = reactionOverlayMessage {
                WhatsAppStyleReactionOverlay(
                    bubbleFrame: reactionBubbleFrames[msg.id] ?? .zero,
                    quickEmojis: chatReactionEmojiUsageStore.orderedQuickReactions(defaults: WhatsAppQuickReactions.primary),
                    onPickEmoji: { emoji in
                        applyChatReaction(message: msg, emoji: emoji)
                    },
                    onDismiss: {
                        reactionOverlayMessage = nil
                        showExtendedReactionEmojis = false
                    },
                    showMoreEmojis: $showExtendedReactionEmojis
                )
                .transition(.opacity)
                .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: reactionOverlayMessage?.id)
        .sheet(isPresented: $showExtendedReactionEmojis) {
            Group {
                if let msg = reactionOverlayMessage {
                    ExtendedEmojiReactionSheet(
                        onPick: { emoji in
                            applyChatReaction(message: msg, emoji: emoji)
                            reactionOverlayMessage = nil
                            showExtendedReactionEmojis = false
                        },
                        onDismiss: { showExtendedReactionEmojis = false }
                    )
                } else {
                    Color.clear
                        .onAppear { showExtendedReactionEmojis = false }
                }
            }
            .preluraGlassModalSheetBackground()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarHidden(false)
        .toolbar {
            ToolbarItem(placement: .principal) {
                NavigationLink(destination: UserProfileView(seller: displayedConversation.recipient, authService: authService)) {
                    HStack(spacing: Theme.Spacing.sm) {
                        chatTitleAvatar(url: displayedConversation.recipient.avatarURL, username: displayedConversation.recipient.username)
                        Text(recipientTitle)
                            .font(.headline)
                            .foregroundColor(Theme.Colors.primaryText)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if isOpenedFromArchive {
                        Button(L10n.string("Restore")) { restoreDisplayedConversation() }
                    } else {
                        Button(L10n.string("Archive")) { archiveDisplayedConversation() }
                    }
                    Button("Report", role: .destructive) {
                        showReportUserSheet = true
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(Theme.Colors.primaryText)
                        .frame(width: Theme.AppBar.buttonSize, height: Theme.AppBar.buttonSize)
                        .contentShape(Rectangle())
                }
            }
        }
        .toolbarBackground(Theme.Colors.background, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $showCounterOfferSheet) {
            OptionsSheet(
                title: L10n.string("Send a new offer"),
                onDismiss: { showCounterOfferSheet = false; counterTargetOffer = nil },
                useCustomCornerRadius: false
            ) {
                OfferModalContent(
                    item: item,
                    listingPrice: nil,
                    onSubmit: { newPrice in
                        showCounterOfferSheet = false
                        let target = counterTargetOffer
                        counterTargetOffer = nil
                        Task {
                            if target?.isRejected == true {
                                await handleCreateNewOffer(offerPrice: newPrice, targetOffer: target)
                            } else {
                                await handleRespondToOffer(action: "COUNTER", offerPrice: newPrice, targetOffer: target)
                            }
                        }
                    },
                    onDismiss: { showCounterOfferSheet = false },
                    isSubmitting: $offerModalSubmitting,
                    errorMessage: $offerError
                )
            }
        }
        .fullScreenCover(item: $payNowPayload) { payload in
            NavigationView {
                PaymentView(products: payload.products, totalPrice: payload.totalPrice, customOffer: true)
                    .environmentObject(authService)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") { payNowPayload = nil }
                        }
                    }
            }
        }
        .sheet(isPresented: $showReportUserSheet) {
            NavigationStack {
                ReportUserView(username: displayedConversation.recipient.username)
                    .environmentObject(authService)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showReportUserSheet = false }
                        }
                    }
            }
        }
        .alert(item: $folderActionError) { err in
            Alert(
                title: Text(err.title),
                message: Text(err.message),
                dismissButton: .default(Text("OK")) { folderActionError = nil }
            )
        }
        .onChange(of: socketUIBridge.chatInboundSequence) { _, _ in
            let convId = displayedConversation.id
            let pairs = socketUIBridge.drainInboundChatMessages()
            let firstBid = pairs.first?.0.backendId.map { String($0) }
            ChatThreadUIUpdateDebugState.shared.recordUIOnChangeDrained(
                conversationId: convId,
                drainedCount: pairs.count,
                firstBackendId: firstBid
            )
            for pair in pairs {
                handleSocketIncomingChatMessage(pair.0, echoMessageUuid: pair.1)
            }
        }
        .onReceive(socketUIBridge.offerChannel) { event in
            handleOfferSocketEvent(event)
        }
        .onReceive(socketUIBridge.orderChannel) { event in
            guard displayedConversation.id != "0" else { return }
            switch event.type {
            case "order_cancellation_event", "order_status_event", "order_issue_created":
                loadConversationAndMessagesFromBackend()
            default:
                break
            }
        }
        .onReceive(socketUIBridge.reactionChannel) { event in
            if isCurrentUser(username: event.username) { return }
            let key = "b:\(event.messageId)"
            ChatMessageReactionsStore.shared.applyRemoteReaction(
                conversationId: displayedConversation.id,
                messageKey: key,
                username: event.username,
                emoji: event.emoji
            )
        }
        .onAppear {
            hasAutoScrolledToBottomForThisChat = false
            if let token = authService.authToken {
                chatService.updateAuthToken(token)
            }
            refreshOfferHistoryLoadingFlagsForCurrentConversation()
            restoreCachedMessagesBeforeLoad()
            loadItemSoldBannerFromPersist()
            if let it = item, let pid = it.productId.flatMap({ Int($0) }), let u = it.thumbnailURLForChrome {
                ChatHeaderProductImageURLStore.persist(productId: pid, url: u)
            }
            refreshItemSoldBannerFromProductState()
            connectWebSocket()
            fetchOfferProductIfNeeded()
            fetchOrderProductIfNeeded()
            loadOffers()
            loadConversationAndMessagesFromBackend()
        }
        .onChange(of: displayedConversation.offer?.id) { _, _ in
            fetchOfferProductIfNeeded()
        }
        .onChange(of: offerProductItem?.status) { _, _ in
            refreshItemSoldBannerFromProductState()
        }
        .onChange(of: item?.status) { _, _ in
            refreshItemSoldBannerFromProductState()
        }
        .onChange(of: displayedConversation.order?.id) { _, _ in
            fetchOrderProductIfNeeded()
        }
        .onChange(of: displayedConversation.id) { _, _ in
            chatCatchUpFromServerTask?.cancel()
            chatCatchUpFromServerTask = nil
            webSocket?.disconnect()
            webSocket = nil
            reconnectTask?.cancel()
            reconnectTask = nil
            remoteTypingIndicator.clear()
            typingKeepaliveTask?.cancel()
            typingKeepaliveTask = nil
            didSendTypingStart = false
            messages = []
            offers = []
            timelineOrder = []
            timestampVisibilityOverrides = [:]
            hasAutoScrolledToBottomForThisChat = false
            refreshOfferHistoryLoadingFlagsForCurrentConversation()
            restoreCachedMessagesBeforeLoad()
            loadItemSoldBannerFromPersist()
            loadOffers()
            loadConversationAndMessagesFromBackend()
            connectWebSocket()
        }
        .onChange(of: newMessage) { _, newValue in
            sendTypingForComposerChange(newValue)
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            // Drop the socket as soon as the app leaves the foreground so the server clears `chat_<id>` presence
            // and chat pushes are not suppressed (receiver must not appear "in room" while backgrounded or inactive).
            if phase == .inactive || phase == .background {
                chatCatchUpFromServerTask?.cancel()
                chatCatchUpFromServerTask = nil
                webSocket?.disconnect()
                webSocket = nil
                reconnectTask?.cancel()
                reconnectTask = nil
                remoteTypingIndicator.clear()
                typingKeepaliveTask?.cancel()
                typingKeepaliveTask = nil
                didSendTypingStart = false
            } else if phase == .active {
                guard displayedConversation.id != "0",
                      let token = authService.refreshToken ?? authService.authToken,
                      !token.isEmpty else { return }
                // Pebble chat_screen: refetch on resume — WS is disconnected while backgrounded, so pull missed rows from GraphQL.
                if oldPhase != .active {
                    loadConversationAndMessagesFromBackend()
                }
                if webSocket == nil {
                    connectWebSocket()
                }
            }
        }
        .onDisappear {
            if !offers.isEmpty {
                Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
            }
            if !timelineOrder.isEmpty {
                Self.timelineOrderCache[displayedConversation.id] = timelineOrder
            }
            if !messages.isEmpty, displayedConversation.id != "0" {
                cacheMessagesForConversation(messages, convId: displayedConversation.id)
            }
            if let last = lastPlainChatMessageForInboxPreview(), displayedConversation.id != "0", let tc = tabCoordinator {
                // Match inbox: preview is the latest plain chat line, not offer/sale/issue bubbles.
                let previewConv = Conversation(
                    id: displayedConversation.id,
                    recipient: displayedConversation.recipient,
                    lastMessage: last.content,
                    lastMessageSenderUsername: last.senderUsername,
                    lastMessageTime: last.timestamp,
                    unreadCount: displayedConversation.unreadCount,
                    offer: displayedConversation.offer,
                    order: displayedConversation.order,
                    offerHistory: displayedConversation.offerHistory
                )
                let previewText = ChatRowView.previewText(
                    for: last.content,
                    conversation: previewConv,
                    currentUsername: authService.username
                ) ?? (last.content.count > 60 ? String(last.content.prefix(57)) + "..." : last.content)
                tc.lastMessagePreviewForConversation = (displayedConversation.id, previewText, last.timestamp)
            }
            webSocket?.disconnect()
            webSocket = nil
            reconnectTask?.cancel()
            reconnectTask = nil
            remoteTypingIndicator.clear()
            typingKeepaliveTask?.cancel()
            typingKeepaliveTask = nil
            didSendTypingStart = false
            chatCatchUpFromServerTask?.cancel()
            chatCatchUpFromServerTask = nil
        }
    }

    private func archiveDisplayedConversation() {
        guard let cid = Int(displayedConversation.id), cid > 0 else { return }
        Task {
            do {
                try await chatService.archiveConversation(conversationId: cid)
                await MainActor.run {
                    tabCoordinator?.pendingArchiveWithUndo = displayedConversation
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    folderActionError = ChatFolderActionError(
                        title: L10n.string("Archive"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func restoreDisplayedConversation() {
        guard let cid = Int(displayedConversation.id), cid > 0 else { return }
        Task {
            do {
                try await chatService.unarchiveConversation(conversationId: cid)
                await MainActor.run {
                    tabCoordinator?.requestInboxListRefresh()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    folderActionError = ChatFolderActionError(
                        title: L10n.string("Restore"),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    /// After receiving sold_confirmation via WebSocket, refetch conversation so we get order from backend when it has been linked.
    private func refetchConversationForOrder() async {
        let convId = displayedConversation.id
        guard let conv = try? await chatService.getConversationById(conversationId: convId, currentUsername: authService.username) else { return }
        await MainActor.run {
            guard displayedConversation.id == convId, conv.order != nil else { return }
            displayedConversation = conv
            rebuildTimelineOrder()
        }
    }

    /// Load conversation (with order) and messages from backend. Order is only from API (single source of truth).
    private func loadConversationAndMessagesFromBackend() {
        guard displayedConversation.id != "0" else { return }
        let convId = displayedConversation.id
        let hadCachedMessages = !messages.isEmpty
        if !hadCachedMessages {
            isLoading = true
        }
        Task {
            let updatedConv: Conversation? = try? await chatService.getConversationById(conversationId: convId, currentUsername: authService.username)
            let fetchedMsgs: [Message]?
            do {
                fetchedMsgs = try await chatService.getMessages(conversationId: convId)
            } catch {
                fetchedMsgs = nil
            }
            await MainActor.run {
                guard displayedConversation.id == convId else { return }
                if let conv = updatedConv {
                    displayedConversation = conv
                    if let hist = conv.offerHistory, !hist.isEmpty {
                        let key = offerCacheKey(convId: convId)

                        // Make ACCEPTED immutable even after a full reload: server offerHistory may downgrade old accepted offers.
                        // Patch server entries whose backendId we previously saw as accepted (including synthetic snapshots),
                        // then keep synthetic snapshot cards only if the server doesn't include the base row.
                        let cached = (!self.offers.isEmpty)
                            ? self.offers
                            : (Self.offerHistoryCache[key] ?? Self.loadOfferHistory(key: key) ?? [])

                        let suffix = Self.acceptedSnapshotBackendIdSuffix
                        var acceptedBaseOffersByBackendId: [String: OfferInfo] = [:]
                        for o in cached {
                            guard let bid = o.backendId else { continue }
                            if bid.hasSuffix(suffix) {
                                let base = String(bid.dropLast(suffix.count))
                                if acceptedBaseOffersByBackendId[base] == nil {
                                    acceptedBaseOffersByBackendId[base] = o
                                }
                            } else if (o.status ?? "").uppercased() == "ACCEPTED" {
                                if acceptedBaseOffersByBackendId[bid] == nil {
                                    acceptedBaseOffersByBackendId[bid] = o
                                }
                            }
                        }

                        var combined = hist
                        for i in combined.indices {
                            guard let bid = combined[i].backendId else { continue }
                            guard let accepted = acceptedBaseOffersByBackendId[bid] else { continue }
                            combined[i] = OfferInfo(
                                id: combined[i].id,
                                backendId: combined[i].backendId,
                                status: "ACCEPTED",
                                offerPrice: accepted.offerPrice,
                                buyer: accepted.buyer,
                                products: accepted.products,
                                createdAt: accepted.createdAt ?? combined[i].createdAt,
                                sentByCurrentUser: accepted.sentByCurrentUser,
                                financialBuyerUsername: accepted.financialBuyerUsername,
                                updatedByUsername: accepted.updatedByUsername ?? combined[i].updatedByUsername
                            )
                        }

                        let serverBackendIds = Set(combined.compactMap { $0.backendId })
                        let snapshotOffers = cached.filter { $0.backendId?.hasSuffix(suffix) == true }
                        for snap in snapshotOffers {
                            guard let bid = snap.backendId, bid.hasSuffix(suffix) else { continue }
                            let base = String(bid.dropLast(suffix.count))
                            guard !serverBackendIds.contains(base) else { continue }
                            guard !combined.contains(where: { $0.backendId == snap.backendId }) else { continue }
                            combined.append(snap)
                        }

                        self.offers = combined
                        Self.offerHistoryCache[key] = combined
                        Self.persistOfferHistory(key: key, offers: combined)
                    }
                }
                if let m = fetchedMsgs {
                    let merged = self.mergedThreadMessages(server: m, local: self.messages)
                    self.messages = merged
                    self.cacheMessagesForConversation(merged, convId: convId)
                } else if self.messages.isEmpty {
                    // Network/decoding failure: avoid wiping the thread with [] (user sees "chat doesn't persist").
                    self.messages = []
                }
                // Do not call loadOffers() here: it can race with the send-success block and overwrite the just-sent offer with stale server data. Offers are loaded on appear and when conversation id changes; loadOffers() also guards against overwriting a recently added offer.
                self.isLoading = false
                self.hasFinishedInitialConversationFetch = true
                self.isLoadingOfferHistory = false
                // `loadOffers()` often ran before messages existed — merge offer payloads from message history here so every past offer id appears as a card.
                self.mergeOffersFromMessages()
                if self.offers.isEmpty, self.displayedConversation.offer != nil {
                    self.loadOffers()
                } else {
                    self.rebuildTimelineOrder()
                }
            }
            if let msgs = fetchedMsgs, !msgs.isEmpty {
                let idsToMarkRead = msgs
                    .filter { !isCurrentUser(username: $0.senderUsername) }
                    .compactMap(\.backendId)
                if !idsToMarkRead.isEmpty {
                    _ = try? await chatService.readMessages(messageIds: idsToMarkRead)
                }
            }
        }
    }

    /// Restore offers from cache or seed from `conversation.offer`, then merge offer rows parsed from **message** JSON (`mergeOffersFromMessages`).
    /// When `conversation.offerHistory` is present (from `conversationById`), use it as the primary source of truth, then merge message-derived rows for any ids missing from the server list.
    /// Important: on first appear, `messages` is usually still empty — we call `mergeOffersFromMessages()` again after `getMessages` in `loadConversationAndMessagesFromBackend()` so full history isn’t dropped.
    /// When we have a "just added" offer (last offer created in the last 60s), do not overwrite with server/cache so the sent price stays visible.
    private func loadOffers() {
        let convId = displayedConversation.id
        let now = Date()
        let lastOfferIsFresh = offers.last.flatMap { last in
            (last.createdAt ?? .distantPast).distance(to: now) <= 60
        } ?? false
        if lastOfferIsFresh {
            rebuildTimelineOrder()
            return
        }
        let cacheKey = offerCacheKey(convId: convId)
        // Avoid showing a single inbox `offer` before `conversationById` returns full `offerHistory` (no memory/disk cache).
        if convId != "0",
           displayedConversation.offer != nil,
           displayedConversation.offerHistory == nil,
           !hasFinishedInitialConversationFetch,
           !hasLocalOfferHistoryCache(convId: convId) {
            offers = []
            rebuildTimelineOrder()
            return
        }
        if let hist = displayedConversation.offerHistory, !hist.isEmpty {
            let list = hist.map { o in
                OfferInfo(id: o.id, backendId: o.backendId, status: o.status, offerPrice: o.offerPrice, buyer: o.buyer, products: o.products, createdAt: o.createdAt ?? Date(), sentByCurrentUser: o.sentByCurrentUser, financialBuyerUsername: o.financialBuyerUsername, updatedByUsername: o.updatedByUsername)
            }

            // Make ACCEPTED immutable even after a full reload: server offerHistory may downgrade old accepted offers.
            // We patch any server entry whose backendId we previously saw as accepted (including synthetic snapshots).
            let cached = Self.offerHistoryCache[cacheKey] ?? Self.loadOfferHistory(key: cacheKey) ?? []
            let suffix = Self.acceptedSnapshotBackendIdSuffix
            var acceptedBaseOffersByBackendId: [String: OfferInfo] = [:]
            for o in cached {
                guard let bid = o.backendId else { continue }
                if bid.hasSuffix(suffix) {
                    let base = String(bid.dropLast(suffix.count))
                    if acceptedBaseOffersByBackendId[base] == nil {
                        acceptedBaseOffersByBackendId[base] = o
                    }
                } else if (o.status ?? "").uppercased() == "ACCEPTED" {
                    if acceptedBaseOffersByBackendId[bid] == nil {
                        acceptedBaseOffersByBackendId[bid] = o
                    }
                }
            }

            var combined = list
            for i in combined.indices {
                guard let bid = combined[i].backendId else { continue }
                guard let accepted = acceptedBaseOffersByBackendId[bid] else { continue }
                combined[i] = OfferInfo(
                    id: combined[i].id,
                    backendId: combined[i].backendId,
                    status: "ACCEPTED",
                    offerPrice: accepted.offerPrice,
                    buyer: accepted.buyer,
                    products: accepted.products,
                    createdAt: accepted.createdAt ?? combined[i].createdAt,
                    sentByCurrentUser: accepted.sentByCurrentUser,
                    financialBuyerUsername: accepted.financialBuyerUsername,
                    updatedByUsername: accepted.updatedByUsername ?? combined[i].updatedByUsername
                )
            }

            // If server didn't include the base offer row, keep the synthetic accepted snapshot so the green card still shows.
            let serverBackendIds = Set(combined.compactMap { $0.backendId })
            let snapshotOffers = cached.filter { $0.backendId?.hasSuffix(suffix) == true }
            for snap in snapshotOffers {
                guard let bid = snap.backendId, bid.hasSuffix(suffix) else { continue }
                let base = String(bid.dropLast(suffix.count))
                // Append only when the base accepted offer isn't present in server list.
                guard !serverBackendIds.contains(base) else { continue }
                guard !combined.contains(where: { $0.backendId == snap.backendId }) else { continue }
                combined.append(snap)
            }

            offers = combined
            Self.offerHistoryCache[cacheKey] = combined
            Self.persistOfferHistory(key: cacheKey, offers: combined)
            mergeOffersFromMessages()
            rebuildTimelineOrder()
            return
        }
        if Self.offerHistoryCache[cacheKey] == nil, let persisted = Self.loadOfferHistory(key: cacheKey), !persisted.isEmpty {
            Self.offerHistoryCache[cacheKey] = persisted.map { o in
                OfferInfo(id: o.id, backendId: o.backendId, status: o.status, offerPrice: o.offerPrice, buyer: o.buyer, products: o.products, createdAt: o.createdAt ?? Date(), sentByCurrentUser: o.sentByCurrentUser, financialBuyerUsername: o.financialBuyerUsername, updatedByUsername: o.updatedByUsername)
            }
        }
        if let cached = Self.offerHistoryCache[cacheKey], !cached.isEmpty {
            var list = cached.map { o in OfferInfo(id: o.id, backendId: o.backendId, status: o.status, offerPrice: o.offerPrice, buyer: o.buyer, products: o.products, createdAt: o.createdAt ?? Date(), sentByCurrentUser: o.sentByCurrentUser, financialBuyerUsername: o.financialBuyerUsername, updatedByUsername: o.updatedByUsername) }
            // If server has an offer that isn't our last cached offer (e.g. counter received), append it so it appears in the thread.
            if let serverOffer = displayedConversation.offer {
                let serverId = serverOffer.id
                // Match any row — not only `last`, or we duplicate when server id matches an older card in the list.
                let alreadyHave = list.contains { $0.backendId == serverId || $0.id == serverId }
                if !alreadyHave {
                    // Sender = opposite of last offer (turn-based); first offer fallback to lastMessageSenderUsername.
                    var fromMe = list.last.map { !$0.sentByCurrentUser } ?? isCurrentUser(username: displayedConversation.lastMessageSenderUsername)
                    var offerPrice = serverOffer.offerPrice
                    if let tc = tabCoordinator {
                        let pendingHere = tc.pendingOfferConversationId.map { $0 == displayedConversation.id } ?? true
                        if tc.pendingOfferJustSent, pendingHere {
                            fromMe = true
                            tc.pendingOfferJustSent = false
                            tc.pendingOfferConversationId = nil
                        }
                        if let sentPrice = tc.pendingOfferPrice, pendingHere {
                            offerPrice = sentPrice
                            tc.pendingOfferPrice = nil
                        }
                    }
                    let newOffer = OfferInfo(id: serverId, backendId: serverId, status: serverOffer.status ?? "PENDING", offerPrice: offerPrice, buyer: serverOffer.buyer, products: serverOffer.products, createdAt: serverOffer.createdAt ?? Date(), sentByCurrentUser: fromMe, financialBuyerUsername: serverOffer.financialBuyerUsername, updatedByUsername: serverOffer.updatedByUsername)
                    list.append(newOffer)
                    Self.offerHistoryCache[cacheKey] = list
                    Self.persistOfferHistory(key: cacheKey, offers: list)
                }
            }
            offers = list
        } else if let serverOffer = displayedConversation.offer {
            let sid = serverOffer.id
            // First offer in cache: use lastMessageSender only. Do NOT use offer.buyer — backend often keeps original buyer on counters (mislabels "You offered").
            var fromMe = isCurrentUser(username: displayedConversation.lastMessageSenderUsername)
            var status = serverOffer.status ?? "PENDING"
            var offerPrice = serverOffer.offerPrice
            if let tc = tabCoordinator {
                let pendingHere = tc.pendingOfferConversationId.map { $0 == displayedConversation.id } ?? true
                if tc.pendingOfferJustSent, pendingHere {
                    fromMe = true
                    let u = status.uppercased()
                    if u == "REJECTED" || u == "CANCELLED" { status = "PENDING" }
                    tc.pendingOfferJustSent = false
                    tc.pendingOfferConversationId = nil
                }
                if let sentPrice = tc.pendingOfferPrice, pendingHere {
                    offerPrice = sentPrice
                    tc.pendingOfferPrice = nil
                }
            }
            offers = [
                OfferInfo(id: sid, backendId: sid, status: status, offerPrice: offerPrice, buyer: serverOffer.buyer, products: serverOffer.products, createdAt: serverOffer.createdAt ?? Date(), sentByCurrentUser: fromMe, financialBuyerUsername: serverOffer.financialBuyerUsername, updatedByUsername: serverOffer.updatedByUsername)
            ]
        } else if displayedConversation.order != nil {
            // After checkout, GraphQL often omits `offer` on the conversation; do not wipe an in-memory thread or disk cache.
            if offers.isEmpty {
                if Self.offerHistoryCache[cacheKey] == nil, let persisted = Self.loadOfferHistory(key: cacheKey), !persisted.isEmpty {
                    Self.offerHistoryCache[cacheKey] = persisted.map { o in
                        OfferInfo(id: o.id, backendId: o.backendId, status: o.status, offerPrice: o.offerPrice, buyer: o.buyer, products: o.products, createdAt: o.createdAt ?? Date(), sentByCurrentUser: o.sentByCurrentUser, updatedByUsername: o.updatedByUsername)
                    }
                }
                if let cached = Self.offerHistoryCache[cacheKey], !cached.isEmpty {
                    offers = cached
                }
            }
        } else {
            offers = []
        }
        mergeOffersFromMessages()
        rebuildTimelineOrder()
    }

    /// Merge in offers derived from message history so intermediate offers (e.g. £750 then £780) all appear; superseded ones show with no buttons.
    private func mergeOffersFromMessages() {
        let convId = displayedConversation.id
        let cacheKey = offerCacheKey(convId: convId)
        var existingIds = Set(offers.compactMap { $0.backendId })
        let products = displayedConversation.offer?.products
        var added: [OfferInfo] = []
        for msg in messages.filter(\.isOfferContent) {
            guard let details = msg.parsedOfferDetails else { continue }
            let idStr = details.offerId
            guard !existingIds.contains(idStr) else { continue }
            let fromMe = isCurrentUser(username: msg.senderUsername)
            let buyer = OfferInfo.OfferUser(username: msg.senderUsername, profilePictureUrl: nil)
            let o = OfferInfo(
                id: msg.id.uuidString,
                backendId: idStr,
                status: "PENDING",
                offerPrice: details.offerPrice,
                buyer: buyer,
                products: products,
                createdAt: msg.timestamp,
                sentByCurrentUser: fromMe,
                financialBuyerUsername: nil
            )
            added.append(o)
            existingIds.insert(idStr)
        }
        guard !added.isEmpty else { return }
        var list = offers + added
        list.sort { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        offers = list
        Self.offerHistoryCache[cacheKey] = list
        Self.persistOfferHistory(key: cacheKey, offers: list)
    }

    /// Case-insensitive username comparison so "testuser" / "Testuser" from backend always count as current user.
    private func isCurrentUser(username: String?) -> Bool {
        let a = (username ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        let b = (authService.username ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        return !a.isEmpty && a == b
    }

    /// Index of our in-flight offer row (nil backendId). Never use `offers.last` alone — that can be someone else's card.
    private func indexOfMyOptimisticOffer() -> Int? {
        offers.lastIndex(where: { $0.backendId == nil && $0.sentByCurrentUser })
    }

    private func isOfferFromOtherUser(_ offer: OfferInfo) -> Bool {
        !offer.sentByCurrentUser
    }

    /// Buyer/seller for the sold banner. Prefer `sold_confirmation` sender as buyer; do not trust offer row `buyer.username` alone (it may be `createdBy` from counters).
    private func inferPartiesForSoldBanner() -> (buyer: String, seller: String, rolesConfirmed: Bool) {
        let current = (authService.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let recipientRaw = displayedConversation.recipient.username.trimmingCharacters(in: .whitespacesAndNewlines)

        func inferSellerGivenBuyer(_ buyer: String) -> String? {
            let b = buyer.lowercased()
            let c = current.lowercased()
            let r = recipientRaw.lowercased()
            if !c.isEmpty, c != b { return current }
            if !r.isEmpty, r != b { return displayedConversation.recipient.username }
            let raw = displayedConversation.offer?.products?.first?.seller?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty == false) ? raw! : nil
        }

        let soldSender = messages.last(where: { $0.isSoldConfirmation })?.senderUsername
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let ss = soldSender, !ss.isEmpty {
            let seller = inferSellerGivenBuyer(ss)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = !seller.isEmpty && seller.lowercased() != ss.lowercased()
            return (ss, seller, ok)
        }

        if !hasFinishedInitialConversationFetch {
            return ("", "", false)
        }

        let offer = displayedConversation.offer
        let trimmedFinancial = offer?.financialBuyerUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buyerFromFinancial = trimmedFinancial.isEmpty ? nil : trimmedFinancial
        let trimmedDisplayBuyer = offer?.buyer?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let buyerCandidate = buyerFromFinancial ?? (trimmedDisplayBuyer.isEmpty ? nil : trimmedDisplayBuyer)

        if let bc = buyerCandidate, !bc.isEmpty {
            let seller = inferSellerGivenBuyer(bc)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let ok = !seller.isEmpty && seller.lowercased() != bc.lowercased()
            return (bc, seller, ok)
        }

        let ps = offer?.products?.first?.seller?.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !ps.isEmpty else { return ("", "", false) }
        let pl = ps.lowercased()
        if recipientRaw.lowercased() == pl, !current.isEmpty {
            return (current, ps, true)
        }
        if current.lowercased() == pl, !recipientRaw.isEmpty {
            return (recipientRaw, ps, true)
        }
        return ("", "", false)
    }

    /// When the API has not yet attached `Conversation.order` (or list fetch omitted it) but `sold_confirmation`
    /// exists in the thread, build the same `OrderInfo` used for `SoldConfirmationCardView` from message JSON.
    private func syntheticOrderInfoFromSoldConfirmation() -> OrderInfo? {
        guard !isSupportConversation else { return nil }
        let soldMsgs = messages.filter { $0.isSoldConfirmation }
        guard let m = soldMsgs.max(by: { $0.timestamp < $1.timestamp }),
              let payload = m.parsedSoldConfirmationPayload else { return nil }
        let parties = inferPartiesForSoldBanner()
        return OrderInfo(
            id: "sold-\(payload.orderId)",
            orderId: payload.orderId,
            price: payload.price,
            buyerUsername: parties.buyer,
            sellerUsername: parties.seller,
            createdAt: m.timestamp,
            rolesConfirmed: parties.rolesConfirmed
        )
    }

    /// Build timeline order by merging offers, messages, and sold event; sort by date.
    private func rebuildTimelineOrder() {
        if displayedConversation.order != nil || messages.contains(where: { $0.isSoldConfirmation }), showItemSoldBanner {
            setItemSoldBannerVisible(false)
        }
        // Keep full offer history after payment so the negotiation thread stays visible; cards are greyed via `forceGreyedOut` when sold (see `isSold`).
        let offerList = offers
        let msgs = displayedMessages
        var entries: [(Date, ChatItem)] = []
        for o in offerList {
            entries.append((o.createdAt ?? .distantPast, .offer(o.id)))
        }
        for m in msgs {
            entries.append((m.timestamp, .message(m.id)))
        }
        if let order = displayedConversation.order, !isSupportConversation {
            let parties = inferPartiesForSoldBanner()
            let orderInfo = OrderInfo.from(
                conversationOrder: order,
                buyerUsername: parties.buyer,
                sellerUsername: parties.seller,
                rolesConfirmed: parties.rolesConfirmed
            )
            entries.append((orderInfo.createdAt, .sold(orderInfo)))
        } else if let synthetic = syntheticOrderInfoFromSoldConfirmation() {
            entries.append((synthetic.createdAt, .sold(synthetic)))
        } else if showItemSoldBanner, displayedConversation.offer != nil {
            let soldBannerTime = messages.last(where: { $0.isSoldConfirmation })?.timestamp
                ?? offerList.last?.createdAt
                ?? msgs.last?.timestamp
                ?? Date()
            entries.append((soldBannerTime, .soldBanner(soldBannerTime)))
        }
        entries.sort { $0.0 < $1.0 }
        timelineOrder = entries.map(\.1)
    }

    /// Create a new offer (same products) when the current offer is declined — backend rejects COUNTER on cancelled offers.
    private func handleCreateNewOffer(offerPrice: Double, targetOffer: OfferInfo? = nil) async {
        guard let offer = targetOffer ?? displayedConversation.offer,
              let productIds = offer.products?.compactMap({ p in p.id.flatMap(Int.init) }),
              !productIds.isEmpty else {
            await MainActor.run { offerError = "Could not load product" }
            return
        }
        await MainActor.run {
            isRespondingToOffer = true
            offerError = nil
            let optimistic = OfferInfo(id: UUID().uuidString, backendId: nil, status: "PENDING", offerPrice: offerPrice, buyer: offer.buyer, products: offer.products, createdAt: Date(), sentByCurrentUser: true, financialBuyerUsername: offer.financialBuyerUsername)
            offers = offers + [optimistic]
            rebuildTimelineOrder()
        }
        do {
            let (_, newConv) = try await productService.createOffer(offerPrice: offerPrice, productIds: productIds, message: nil)
            let convs = try await chatService.getConversations()
            await MainActor.run {
                if let updated = convs.first(where: { $0.id == displayedConversation.id }) {
                    displayedConversation = updated
                }
                let serverOfferFromCreate = (newConv?.id == displayedConversation.id ? newConv?.offer : nil)
                let rawStatus = serverOfferFromCreate?.status ?? "PENDING"
                let status: String = {
                    let u = rawStatus.uppercased()
                    if u == "REJECTED" || u == "CANCELLED" { return "PENDING" }
                    return rawStatus
                }()
                let newBackendId = serverOfferFromCreate?.id
                // WebSocket may have already appended this offer — only remove our duplicate placeholder, never other cards.
                if let bid = newBackendId, offers.contains(where: { $0.backendId == bid }) {
                    if let optIdx = indexOfMyOptimisticOffer() {
                        var next = offers
                        next.remove(at: optIdx)
                        offers = next
                    }
                    Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                    Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                    rebuildTimelineOrder()
                    isRespondingToOffer = false
                    offerError = nil
                    return
                }
                guard let optIdx = indexOfMyOptimisticOffer() else {
                    isRespondingToOffer = false
                    offerError = nil
                    return
                }
                let stableId = offers[optIdx].id
                let confirmed = OfferInfo(
                    id: stableId,
                    backendId: newBackendId,
                    status: status,
                    offerPrice: offerPrice,
                    buyer: serverOfferFromCreate?.buyer ?? offer.buyer,
                    products: serverOfferFromCreate?.products ?? offer.products,
                    createdAt: offers[optIdx].createdAt ?? Date(),
                    sentByCurrentUser: true,
                    financialBuyerUsername: serverOfferFromCreate?.financialBuyerUsername ?? offer.financialBuyerUsername
                )
                var nextOffers = offers
                nextOffers[optIdx] = confirmed
                offers = nextOffers
                Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                rebuildTimelineOrder()
                isRespondingToOffer = false
                offerError = nil
            }
        } catch {
            await MainActor.run {
                if let optIdx = indexOfMyOptimisticOffer() {
                    var next = offers
                    next.remove(at: optIdx)
                    offers = next
                    rebuildTimelineOrder()
                }
                isRespondingToOffer = false
                let msg = error.localizedDescription
                if isOfferProductUnavailableMessage(msg) {
                    setItemSoldBannerVisible(true)
                    offerError = nil
                } else {
                    offerError = msg
                }
            }
        }
    }

    private func handleRespondToOffer(action: String, offerPrice: Double? = nil, targetOffer: OfferInfo? = nil) async {
        let effectiveOffer = targetOffer ?? displayedConversation.offer
        guard let offer = effectiveOffer, let offerId = offer.offerIdInt else { return }
        let isCounter = action == "COUNTER"
        let newPrice = offerPrice ?? offer.offerPrice
        if isCounter {
            await MainActor.run {
                let optimistic = OfferInfo(id: UUID().uuidString, backendId: nil, status: "PENDING", offerPrice: newPrice, buyer: offer.buyer, products: offer.products, createdAt: Date(), sentByCurrentUser: true, financialBuyerUsername: offer.financialBuyerUsername)
                offers = offers + [optimistic]
                rebuildTimelineOrder()
            }
        }
        await MainActor.run {
            isRespondingToOffer = true
            offerError = nil
        }
        do {
            try await productService.respondToOffer(action: action, offerId: offerId, offerPrice: offerPrice)
            let convs = try await chatService.getConversations()
            await MainActor.run {
                guard let updated = convs.first(where: { $0.id == displayedConversation.id }) else {
                    isRespondingToOffer = false
                    offerError = nil
                    return
                }
                displayedConversation = updated
                if isCounter {
                    let serverOffer = updated.offer
                    let rawStatus = serverOffer?.status ?? "PENDING"
                    let status: String = (rawStatus.uppercased() == "REJECTED" || rawStatus.uppercased() == "CANCELLED") ? "PENDING" : rawStatus
                    let newBackendId = serverOffer?.id
                    let oldOfferIdStr = String(offerId)
                    // If server returns the *old* offer we countered (stale), we must not remove our optimistic row — that would collapse the new card into the old one. Only "remove optimistic" when the duplicate is the *new* offer (WS already added it).
                    let serverReturnedOldOfferId = newBackendId.map { $0 == oldOfferIdStr } ?? false
                    if let bid = newBackendId, !serverReturnedOldOfferId, offers.contains(where: { $0.backendId == bid }) {
                        if let optIdx = indexOfMyOptimisticOffer() {
                            var next = offers
                            next.remove(at: optIdx)
                            offers = next
                        }
                        Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                        Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                        rebuildTimelineOrder()
                        isRespondingToOffer = false
                        offerError = nil
                        return
                    }
                    guard let optIdx = indexOfMyOptimisticOffer() else {
                        isRespondingToOffer = false
                        offerError = nil
                        return
                    }
                    let stableId = offers[optIdx].id
                    // When server returned the old offer id, keep our card's backendId nil so we don't duplicate that id; WS will send the real new id later and we'll upgrade this row.
                    let confirmedBackendId = serverReturnedOldOfferId ? nil : newBackendId
                    let confirmed = OfferInfo(
                        id: stableId,
                        backendId: confirmedBackendId,
                        status: status,
                        offerPrice: newPrice,
                        buyer: serverOffer?.buyer ?? offer.buyer,
                        products: serverOffer?.products ?? offer.products,
                        createdAt: offers[optIdx].createdAt ?? Date(),
                        sentByCurrentUser: true,
                        financialBuyerUsername: serverOffer?.financialBuyerUsername ?? offer.financialBuyerUsername
                    )
                    var nextOffers = offers
                    nextOffers[optIdx] = confirmed
                    offers = nextOffers
                    Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                    Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                    rebuildTimelineOrder()
                } else if action == "ACCEPT" || action == "REJECT", let serverOffer = updated.offer {
                    let targetId = String(offerId)
                    if let idx = offers.firstIndex(where: { $0.backendId == targetId || $0.id == targetId }) {
                        let last = offers[idx]

                        // IMPORTANT:
                        // `getConversations()` returns only the conversation's current offer as `updated.offer`,
                        // which may not match the offer card the user just tapped (targetId).
                        // So we MUST not blindly copy `serverOffer.status` onto the tapped card.
                        let serverOfferId = serverOffer.backendId ?? serverOffer.id
                        let serverMatchesTarget = serverOfferId == targetId

                        let existingUpper = (last.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()

                        let resolvedStatus: String = {
                            // Once green, always green (history).
                            if existingUpper == "ACCEPTED" { return "ACCEPTED" }

                            switch action {
                            case "ACCEPT":
                                return "ACCEPTED"
                            case "REJECT":
                                // Only trust server status when it matches the tapped offer id.
                                guard serverMatchesTarget else { return "REJECTED" }
                                let incomingUpper = (serverOffer.status ?? last.status ?? "REJECTED")
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .uppercased()
                                return incomingUpper == "CANCELLED" ? "CANCELLED" : "REJECTED"
                            default:
                                return last.status ?? "PENDING"
                            }
                        }()

                        // Keep price/buyer/products stable unless the server matches the tapped offer id.
                        let offerPrice = serverMatchesTarget ? serverOffer.offerPrice : last.offerPrice
                        let buyer = serverMatchesTarget ? serverOffer.buyer : last.buyer
                        let products = serverMatchesTarget ? serverOffer.products : last.products
                        let resolvedUpdatedBy: String? = {
                            if action == "ACCEPT", resolvedStatus.uppercased() == "ACCEPTED" {
                                return authService.username ?? (serverMatchesTarget ? serverOffer.updatedByUsername : last.updatedByUsername)
                            }
                            return serverMatchesTarget ? serverOffer.updatedByUsername : last.updatedByUsername
                        }()

                        let updatedOffer = OfferInfo(
                            id: last.id,
                            backendId: last.backendId,
                            status: resolvedStatus,
                            offerPrice: offerPrice,
                            buyer: buyer,
                            products: products,
                            createdAt: last.createdAt ?? Date(),
                            sentByCurrentUser: last.sentByCurrentUser,
                            financialBuyerUsername: serverMatchesTarget ? serverOffer.financialBuyerUsername : last.financialBuyerUsername,
                            updatedByUsername: resolvedUpdatedBy
                        )
                        var nextOffers = offers
                        nextOffers[idx] = updatedOffer
                        offers = nextOffers
                        Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                        Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                        rebuildTimelineOrder()
                    }
                }
                isRespondingToOffer = false
                offerError = nil
            }
        } catch {
            await MainActor.run {
                if isCounter, let optIdx = indexOfMyOptimisticOffer() {
                    var next = offers
                    next.remove(at: optIdx)
                    offers = next
                    rebuildTimelineOrder()
                }
                isRespondingToOffer = false
                let msg = error.localizedDescription
                if isOfferProductUnavailableMessage(msg) {
                    setItemSoldBannerVisible(true)
                    offerError = nil
                } else {
                    offerError = msg
                }
            }
        }
    }

    /// Opens checkout for the accepted-offer price. Uses the specific card’s products/price when present (offer thread), else falls back to the conversation’s current offer.
    private func presentPayNow(for cardOffer: OfferInfo) {
        let fallbackProducts = displayedConversation.offer?.products
        let productSource = (cardOffer.products?.isEmpty == false) ? cardOffer.products : fallbackProducts
        let productIds = productSource?.compactMap { p -> Int? in
            guard let id = p.id else { return nil }
            return Int(id)
        } ?? []
        guard !productIds.isEmpty else { return }
        let offerPrice = cardOffer.offerPrice
        Task {
            do {
                var items: [Item] = []
                for id in productIds {
                    guard let product = try await productService.getProduct(id: id) else {
                        throw NSError(
                            domain: "ChatDetailView",
                            code: 404,
                            userInfo: [NSLocalizedDescriptionKey: "Could not load product"]
                        )
                    }
                    items.append(product)
                }
                await MainActor.run {
                    payNowPayload = PayNowPayload(products: items, totalPrice: offerPrice)
                }
            } catch {
                await MainActor.run {
                    let msg = error.localizedDescription
                    if isOfferProductUnavailableMessage(msg) {
                        setItemSoldBannerVisible(true)
                        offerError = nil
                    } else {
                        offerError = msg
                    }
                }
            }
        }
    }

    /// Order header bar: shown in every chat that has an order. Loads the related product so the top bar
    /// shows thumbnail, name, price, status and is tappable to product. Fetched in onAppear and when order changes.
    /// Price rule: use the latest accepted offer price when available; fallback to order total.
    private var latestAcceptedOfferPriceForHeader: Double? {
        offers
            .filter { $0.isAccepted }
            .max(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) })?
            .offerPrice
    }

    /// Sum of line list prices when every line has a price (multi-buy header subtotal).
    private var orderHeaderMultibuySubtotal: Double? {
        guard let order = displayedConversation.order, order.isMultibuy else { return nil }
        let prices = order.lineItems.compactMap(\.price)
        guard prices.count == order.lineItems.count, !prices.isEmpty else { return nil }
        return prices.reduce(0, +)
    }

    /// Line-item price for the header: agreed offer or fetched product price. Nil until loaded — do not show `order.total` (often items + delivery) to avoid flashing wrong amount.
    private var orderHeaderLinePriceForDisplay: Double? {
        guard displayedConversation.order != nil else { return nil }
        if let sub = orderHeaderMultibuySubtotal { return sub }
        if let p = latestAcceptedOfferPriceForHeader { return p }
        if let item = orderProductItem { return item.price }
        return nil
    }

    private var orderHeaderBar: some View {
        guard let order = displayedConversation.order else { return AnyView(EmptyView()) }
        if order.isMultibuy {
            return AnyView(multibuyOrderHeaderBar(order: order))
        }
        let orderProductId = order.firstProductId.flatMap { Int($0) }
        let rawOrderImage = orderProductItem?.thumbnailURLForChrome
            ?? order.firstProductImageUrl.flatMap { ProductListImageURL.preferredString(from: $0) ?? $0 }
            ?? orderProductId.flatMap { ChatHeaderProductImageURLStore.url(forProductId: $0) }
        let trimmedOrderImage = rawOrderImage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let orderThumb: (url: URL?, invalidURL: Bool) = {
            guard let t = trimmedOrderImage, !t.isEmpty else { return (nil, false) }
            if let u = URL(string: t) { return (u, false) }
            return (nil, true)
        }()
        let bar = HStack(spacing: Theme.Spacing.md) {
            ChatHeaderProductThumbnail(imageURL: orderThumb.url, invalidURLFromAPI: orderThumb.invalidURL)
            VStack(alignment: .leading, spacing: 2) {
                Text(order.firstProductName ?? "Order")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                if let line = orderHeaderLinePriceForDisplay {
                    Text(CurrencyFormatter.gbp(line))
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.primaryColor)
                } else {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(Theme.primaryColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 22)
                }
                Text(orderHeaderStatusText(order: order))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.primaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, ChatThreadLayout.horizontalGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .contentShape(Rectangle())
        if let detailOrder = conversationOrderForDetail {
            return AnyView(
                NavigationLink(destination: OrderDetailView(order: detailOrder, isSeller: isSellerForOrderDetail)) { bar }
                    .buttonStyle(PlainTappableButtonStyle())
            )
        }
        return AnyView(bar)
    }

    private func multibuyOrderHeaderBar(order: ConversationOrder) -> AnyView {
        let bar = HStack(spacing: Theme.Spacing.md) {
            TabView {
                ForEach(order.lineItems) { line in
                    let raw = line.imageUrl.flatMap { ProductListImageURL.preferredString(from: $0) ?? $0 }?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let parsed = URL(string: raw)
                    let invalid = !raw.isEmpty && parsed == nil
                    ChatHeaderProductThumbnail(imageURL: parsed, invalidURLFromAPI: invalid)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(width: 72, height: 72)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text("Multibuy")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                Text("\(order.lineItems.count) items")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                if let sub = orderHeaderMultibuySubtotal {
                    Text(CurrencyFormatter.gbp(sub))
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.primaryColor)
                } else {
                    ProgressView()
                        .scaleEffect(0.9)
                        .tint(Theme.primaryColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 22)
                }
                Text(orderHeaderStatusText(order: order))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.primaryColor)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, ChatThreadLayout.horizontalGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .contentShape(Rectangle())

        if let detailOrder = conversationOrderForDetail {
            return AnyView(
                NavigationLink(destination: OrderDetailView(order: detailOrder, isSeller: isSellerForOrderDetail)) { bar }
                    .buttonStyle(PlainTappableButtonStyle())
            )
        }
        return AnyView(bar)
    }

    /// Map conversation order summary to full Order model for navigation from chat header.
    private var conversationOrderForDetail: Order? {
        guard let order = displayedConversation.order else { return nil }
        let products: [OrderProductSummary] = {
            if !order.lineItems.isEmpty {
                return order.lineItems.map { line in
                    OrderProductSummary(
                        id: line.productId,
                        name: line.name.isEmpty ? "Item" : line.name,
                        imageUrl: line.imageUrl,
                        price: line.price.map { String(format: "%.2f", $0) },
                        condition: nil,
                        colors: [],
                        style: nil,
                        size: nil,
                        brand: nil,
                        materials: []
                    )
                }
            }
            let product = OrderProductSummary(
                id: order.firstProductId ?? "0",
                name: order.firstProductName ?? "Order item",
                imageUrl: order.firstProductImageUrl,
                price: orderHeaderLinePriceForDisplay.map { String(format: "%.2f", $0) },
                condition: nil,
                colors: [],
                style: nil,
                size: nil,
                brand: nil,
                materials: []
            )
            return [product]
        }()
        return Order(
            id: order.id,
            publicId: order.publicId,
            priceTotal: String(format: "%.2f", order.total),
            discountPrice: nil,
            status: order.status,
            createdAt: order.createdAt ?? Date(),
            otherParty: displayedConversation.recipient,
            products: products,
            shippingAddress: nil,
            shipmentService: nil,
            deliveryDate: nil,
            trackingNumber: nil,
            trackingUrl: nil,
            buyerOrderCountWithSeller: nil,
            cancellation: nil
        )
    }

    private func orderStatusDisplay(_ status: String) -> String {
        switch status {
        case "CONFIRMED": return "Confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED": return "Cancelled"
        case "REFUNDED": return "Refunded"
        default: return status
        }
    }

    private func orderHeaderStatusText(order: ConversationOrder) -> String {
        if messages.contains(where: { $0.isOrderIssue }) {
            return "Order on hold"
        }
        return orderStatusDisplay(order.status)
    }

    private var offerProductHeaderBar: some View {
        let offer = displayedConversation.offer!
        let priceStr = CurrencyFormatter.gbp(offer.offerPrice)
        let offerProductId = offer.products?.first?.id.flatMap { Int($0) }
        let rawOfferImage = offerProductItem?.thumbnailURLForChrome
            ?? offerProductId.flatMap { ChatHeaderProductImageURLStore.url(forProductId: $0) }
        let trimmedOfferImage = rawOfferImage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let offerThumb: (url: URL?, invalidURL: Bool) = {
            guard let t = trimmedOfferImage, !t.isEmpty else { return (nil, false) }
            if let u = URL(string: t) { return (u, false) }
            return (nil, true)
        }()
        let soldStyleActive = showItemSoldBanner && displayedConversation.order == nil
        let bar = HStack(spacing: Theme.Spacing.md) {
            ChatHeaderProductThumbnail(
                imageURL: offerThumb.url,
                invalidURLFromAPI: offerThumb.invalidURL,
                soldOverlayActive: false
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(offerProductItem?.title ?? offer.products?.first?.name ?? "Product")
                    .font(Theme.Typography.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(priceStr)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.primaryColor)
                    if soldStyleActive {
                        Text(L10n.string("Sold"))
                            .font(Theme.Typography.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.primaryColor)
                            .cornerRadius(8)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, ChatThreadLayout.horizontalGutter)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
        .contentShape(Rectangle())
        return Group {
            if let item = offerProductItem {
                NavigationLink(destination: ItemDetailView(item: item, authService: authService)) { bar }
                    .buttonStyle(PlainTappableButtonStyle())
            } else {
                bar
            }
        }
    }

    /// Inline “sold” notice: same card treatment as offer rows (secondary background + border).
    private var itemSoldPersistentBanner: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            Image(systemName: "tag.slash.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(L10n.string("This item has been sold"))
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
        .accessibilityIdentifier("chat_item_sold_banner")
    }

    private func fetchOfferProductIfNeeded() {
        guard let offer = displayedConversation.offer,
              let firstId = offer.products?.first?.id.flatMap({ Int($0) }) else {
            offerProductItem = nil
            return
        }
        if let cached = Self.offerProductCache[firstId] {
            offerProductItem = cached
            if let u = cached.thumbnailURLForChrome {
                ChatHeaderProductImageURLStore.persist(productId: firstId, url: u)
            }
            return
        }
        Task {
            if let product = try? await productService.getProduct(id: firstId) {
                await MainActor.run {
                    Self.offerProductCache[firstId] = product
                    offerProductItem = product
                    if let u = product.thumbnailURLForChrome {
                        ChatHeaderProductImageURLStore.persist(productId: firstId, url: u)
                    }
                    if product.status.uppercased() != "ACTIVE",
                       displayedConversation.order == nil,
                       !messages.contains(where: { $0.isSoldConfirmation }) {
                        setItemSoldBannerVisible(true)
                    }
                }
            }
        }
    }

    private func fetchOrderProductIfNeeded() {
        guard let order = displayedConversation.order,
              let firstId = order.firstProductId.flatMap({ Int($0) }) else {
            orderProductItem = nil
            return
        }
        if let cached = Self.orderProductCache[firstId] {
            orderProductItem = cached
            if let u = cached.thumbnailURLForChrome {
                ChatHeaderProductImageURLStore.persist(productId: firstId, url: u)
            }
            return
        }
        Task {
            if let product = try? await productService.getProduct(id: firstId) {
                await MainActor.run {
                    Self.orderProductCache[firstId] = product
                    orderProductItem = product
                    if let u = product.thumbnailURLForChrome {
                        ChatHeaderProductImageURLStore.persist(productId: firstId, url: u)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chatTitleAvatar(url: String?, username: String) -> some View {
        if PreluraSupportBranding.isSupportRecipient(username: username) {
            PreluraSupportBranding.supportAvatar(size: Self.chatAvatarSize)
        } else {
            Group {
                if let u = url, !u.isEmpty, let parsed = URL(string: u) {
                    AsyncImage(url: parsed) { phase in
                        switch phase {
                        case .success(let img):
                            img.resizable().scaledToFill()
                        case .failure:
                            chatAvatarPlaceholder(username: username)
                        case .empty:
                            chatAvatarPlaceholder(username: username)
                        @unknown default:
                            chatAvatarPlaceholder(username: username)
                        }
                    }
                } else {
                    chatAvatarPlaceholder(username: username)
                }
            }
            .frame(width: Self.chatAvatarSize, height: Self.chatAvatarSize)
            .clipShape(Circle())
        }
    }

    private func chatAvatarPlaceholder(username: String) -> some View {
        Circle()
            .fill(Theme.Colors.secondaryBackground)
            .overlay(
                Text(String((username.isEmpty ? "?" : username).prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.Colors.secondaryText)
            )
    }

    /// When the backend reuses the same offer id for a counter (new price), keep the previous card and append the new one.
    private func demoteExistingOfferRowForReusedServerId(existingIndex: Int, incoming: OfferInfo, event: OfferSocketEvent) {
        let existing = offers[existingIndex]
        let demotedBackendId = "\(incoming.id)-hist-\(Int(existing.offerPrice * 100))-\(existing.id.replacingOccurrences(of: "-", with: "").prefix(8))"
        var next = offers
        next[existingIndex] = OfferInfo(
            id: existing.id,
            backendId: demotedBackendId,
            status: existing.status,
            offerPrice: existing.offerPrice,
            buyer: existing.buyer,
            products: existing.products,
            createdAt: existing.createdAt ?? Date(),
            sentByCurrentUser: existing.sentByCurrentUser,
            financialBuyerUsername: existing.financialBuyerUsername,
            updatedByUsername: existing.updatedByUsername
        )
        let senderNorm = event.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitMine: Bool? = {
            guard let s = senderNorm, !s.isEmpty else { return nil }
            return isCurrentUser(username: s)
        }()
        // Receiving side: default to "from peer" when sender is missing (avoids wrong `!lastOffer.sentByCurrentUser` flip).
        let sentByMe = explicitMine ?? false
        let displayBuyer: OfferInfo.OfferUser?
        if let s = senderNorm, !s.isEmpty {
            displayBuyer = OfferInfo.OfferUser(username: s, profilePictureUrl: incoming.buyer?.profilePictureUrl)
        } else {
            displayBuyer = incoming.buyer
        }
        let newRow = OfferInfo(
            id: UUID().uuidString,
            backendId: incoming.id,
            status: incoming.status,
            offerPrice: incoming.offerPrice,
            buyer: displayBuyer,
            products: incoming.products ?? existing.products,
            createdAt: incoming.createdAt ?? Date(),
            sentByCurrentUser: sentByMe,
            financialBuyerUsername: incoming.financialBuyerUsername ?? existing.financialBuyerUsername,
            updatedByUsername: incoming.updatedByUsername
        )
        next.append(newRow)
        offers = next
    }

    /// Handle NEW_OFFER / UPDATE_OFFER from WebSocket. When backend pushes these, update offers without refetch.
    private func handleOfferSocketEvent(_ event: OfferSocketEvent) {
        if let convId = event.conversationId, convId != displayedConversation.id { return }
        switch event.type {
        case "NEW_OFFER":
            guard let offer = event.offer else { break }
            let senderNorm = event.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
            let explicitSenderIsMine: Bool? = {
                guard let s = senderNorm, !s.isEmpty else { return nil }
                return isCurrentUser(username: s)
            }()
            // Backend often keeps the same offer row id when someone counters — `contains(backendId)` would skip and we'd show one card. Split history instead.
            if let dupIdx = offers.firstIndex(where: { $0.backendId == offer.id }),
               abs(offers[dupIdx].offerPrice - offer.offerPrice) > 0.009 {
                demoteExistingOfferRowForReusedServerId(existingIndex: dupIdx, incoming: offer, event: event)
                Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                rebuildTimelineOrder()
                break
            }
            // If we already have this offer id but didn't demote (e.g. same price), still correct the card's sender when backend sends it (fixes misattribution from cache/API).
            if let existingIdx = offers.firstIndex(where: { $0.backendId == offer.id }),
               let sender = senderNorm, !sender.isEmpty,
               !offers[existingIdx].sentByCurrentUser,
               offers[existingIdx].buyer?.username?.lowercased() != sender.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                let o = offers[existingIdx]
                let corrected = OfferInfo(
                    id: o.id,
                    backendId: o.backendId,
                    status: o.status,
                    offerPrice: o.offerPrice,
                    buyer: OfferInfo.OfferUser(username: sender, profilePictureUrl: o.buyer?.profilePictureUrl),
                    products: o.products,
                    createdAt: o.createdAt ?? Date(),
                    sentByCurrentUser: false,
                    financialBuyerUsername: o.financialBuyerUsername,
                    updatedByUsername: o.updatedByUsername
                )
                var next = offers
                next[existingIdx] = corrected
                offers = next
                Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
                Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
                rebuildTimelineOrder()
                break
            }
            // Never replace optimistic rows via WebSocket — only append (dedupe by server offer id).
            if !offers.contains(where: { $0.backendId == offer.id }) {
                let isMineForNew: Bool
                if let explicit = explicitSenderIsMine {
                    isMineForNew = explicit
                } else if let lastMsg = messages.reversed().first(where: { $0.isOfferContent }),
                          let details = lastMsg.parsedOfferDetails,
                          details.offerId == offer.id {
                    isMineForNew = isCurrentUser(username: lastMsg.senderUsername)
                } else {
                    // Do NOT infer from `offers.last` — when the peer counters twice in a row or messages lag, `!last.sentByCurrentUser` becomes true and we mis-label their offer as ours (and can hit the optimistic-upgrade path).
                    isMineForNew = false
                }
                #if DEBUG
                print("---- OFFER EVENT ----")
                print("senderUsername:", event.senderUsername ?? "nil")
                print("last message sender:", messages.last?.senderUsername ?? "nil")
                print("current user:", authService.username ?? "nil")
                print("isMineForNew:", isMineForNew)
                print("---------------------")
                #endif
                let sender = senderNorm
                let displayBuyer: OfferInfo.OfferUser?
                if let s = sender, !s.isEmpty {
                    displayBuyer = OfferInfo.OfferUser(username: s, profilePictureUrl: offer.buyer?.profilePictureUrl)
                } else {
                    displayBuyer = offer.buyer
                }
                // Only upgrade a nil-backend placeholder when we know this event is ours (explicit sender or inferred mine).
                if isMineForNew, explicitSenderIsMine != false, let optIdx = indexOfMyOptimisticOffer() {
                    let existing = offers[optIdx]
                    let upgraded = OfferInfo(
                        id: existing.id,
                        backendId: offer.id,
                        status: offer.status,
                        offerPrice: offer.offerPrice,
                        buyer: displayBuyer ?? existing.buyer,
                        products: offer.products ?? existing.products,
                        createdAt: offer.createdAt ?? existing.createdAt ?? Date(),
                        sentByCurrentUser: true,
                        financialBuyerUsername: offer.financialBuyerUsername ?? existing.financialBuyerUsername,
                        updatedByUsername: offer.updatedByUsername ?? existing.updatedByUsername
                    )
                    var nextOffers = offers
                    nextOffers[optIdx] = upgraded
                    offers = nextOffers
                    isRespondingToOffer = false
                    offerError = nil
                } else {
                    let newOffer = OfferInfo(
                        id: UUID().uuidString,
                        backendId: offer.id,
                        status: offer.status,
                        offerPrice: offer.offerPrice,
                        buyer: displayBuyer,
                        products: offer.products,
                        createdAt: offer.createdAt ?? Date(),
                        sentByCurrentUser: isMineForNew,
                        financialBuyerUsername: offer.financialBuyerUsername,
                        updatedByUsername: offer.updatedByUsername
                    )
                    offers.append(newOffer)
                    if isMineForNew {
                        isRespondingToOffer = false
                        offerError = nil
                    }
                }
            }
            Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
            Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
            rebuildTimelineOrder()
        case "UPDATE_OFFER":
            guard let offerId = event.offerId ?? event.offer?.id, let status = event.status,
                  let idx = offers.firstIndex(where: { $0.id == offerId || $0.backendId == offerId || $0.id.hasPrefix(offerId + "-") }) else { break }
            let o = offers[idx]
            let normalizedIncomingStatus = status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let existingUpper = (o.status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            let incomingUpper = normalizedIncomingStatus
            // Make ACCEPTED immutable for history: once a card is green, it must never flip to declined/red.
            let resolvedStatus: String =
                (existingUpper == "ACCEPTED" && (incomingUpper == "REJECTED" || incomingUpper == "CANCELLED"))
                ? "ACCEPTED"
                : normalizedIncomingStatus

            let acceptorForPreview: String? = {
                guard resolvedStatus.uppercased() == "ACCEPTED" else { return o.updatedByUsername }
                let fromEvent = event.senderUsername?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let fromEvent, !fromEvent.isEmpty { return fromEvent }
                return o.updatedByUsername
            }()
            var nextOffers = offers
            nextOffers[idx] = OfferInfo(
                id: o.id,
                backendId: o.backendId,
                status: resolvedStatus,
                offerPrice: o.offerPrice,
                buyer: o.buyer,
                products: o.products,
                createdAt: o.createdAt ?? Date(),
                sentByCurrentUser: o.sentByCurrentUser,
                financialBuyerUsername: o.financialBuyerUsername,
                updatedByUsername: acceptorForPreview
            )
            offers = nextOffers
            Self.offerHistoryCache[offerCacheKey(convId: displayedConversation.id)] = offers
            Self.persistOfferHistory(key: offerCacheKey(convId: displayedConversation.id), offers: offers)
            rebuildTimelineOrder()
        default:
            break
        }
        notifyInboxListShouldRefresh()
    }

    private func notifyInboxListShouldRefresh() {
        tabCoordinator?.requestInboxListRefresh()
    }

    private func publishInboxPreviewFromMessage(_ msg: Message) {
        guard displayedConversation.id != "0",
              let tc = tabCoordinator else { return }
        let previewConversation = Conversation(
            id: displayedConversation.id,
            recipient: displayedConversation.recipient,
            lastMessage: msg.content,
            lastMessageSenderUsername: msg.senderUsername,
            lastMessageTime: msg.timestamp,
            unreadCount: displayedConversation.unreadCount,
            offer: displayedConversation.offer,
            order: displayedConversation.order,
            offerHistory: displayedConversation.offerHistory
        )
        let previewText = ChatRowView.previewText(
            for: msg.content,
            conversation: previewConversation,
            currentUsername: authService.username
        ) ?? (msg.content.count > 60 ? String(msg.content.prefix(57)) + "..." : msg.content)
        tc.lastMessagePreviewForConversation = (displayedConversation.id, previewText, msg.timestamp)
    }

    private func scheduleSocketReconnect(reason: String) {
        guard scenePhase == .active,
              displayedConversation.id != "0",
              webSocket == nil else { return }
        reconnectTask?.cancel()
        reconnectAttempt += 1
        let delaySeconds = min(8, 1 << min(reconnectAttempt, 3))
        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delaySeconds) * 1_000_000_000)
            await MainActor.run {
                guard scenePhase == .active,
                      displayedConversation.id != "0",
                      webSocket == nil else { return }
                ChatPushTraceDebugState.shared.markSocketTraffic(
                    conversationId: displayedConversation.id,
                    summary: "reconnect attempt \(reconnectAttempt) after \(reason)"
                )
                connectWebSocket()
            }
        }
    }

    /// Light GraphQL reload shortly after a socket row (same idea as `loadConversationAndMessagesFromBackend` for order events).
    private func scheduleDebouncedChatCatchUpFromServer() {
        chatCatchUpFromServerTask?.cancel()
        let convId = displayedConversation.id
        guard convId != "0" else { return }
        chatCatchUpFromServerTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, displayedConversation.id == convId else { return }
            loadMessages()
        }
    }

    /// Applies a chat row from the socket on the main thread via `onReceive` (not from a WS closure capturing this view).
    private func handleSocketIncomingChatMessage(_ msg: Message, echoMessageUuid: String?) {
        let convIdForPushTrace = displayedConversation.id
        if let pending = pendingMessageUUID, echoMessageUuid == pending,
           let idx = messages.firstIndex(where: { $0.id.uuidString == pending }) {
            let oldKey = "u:\(pending)"
            let newKey = ChatMessageReactionsStore.stableKey(for: msg)
            ChatMessageReactionsStore.shared.migrateMessageKey(
                conversationId: displayedConversation.id,
                from: oldKey,
                to: newKey
            )
            var next = messages
            next[idx] = msg
            next.sort { $0.timestamp < $1.timestamp }
            messages = next
            pendingMessageUUID = nil
            if msg.isOfferContent {
                mergeOffersFromMessages()
            }
            rebuildTimelineOrder()
            ChatPushTraceDebugState.shared.markSocketTraffic(conversationId: convIdForPushTrace, summary: "message_received_echo")
            publishInboxPreviewFromMessage(msg)
            notifyInboxListShouldRefresh()
            scheduleDebouncedChatCatchUpFromServer()
            ChatThreadUIUpdateDebugState.shared.recordUIHandlerOutcome(
                conversationId: convIdForPushTrace,
                backendId: msg.backendId,
                outcome: "echo_replace optimistic→server"
            )
            return
        }
        if let bid = msg.backendId, let idx = messages.firstIndex(where: { $0.backendId == bid }) {
            var next = messages
            next[idx] = msg
            next.sort { $0.timestamp < $1.timestamp }
            messages = next
            if msg.isOfferContent {
                mergeOffersFromMessages()
            }
            rebuildTimelineOrder()
            ChatPushTraceDebugState.shared.markSocketTraffic(conversationId: convIdForPushTrace, summary: "message_received_merge")
            publishInboxPreviewFromMessage(msg)
            notifyInboxListShouldRefresh()
            scheduleDebouncedChatCatchUpFromServer()
            ChatThreadUIUpdateDebugState.shared.recordUIHandlerOutcome(
                conversationId: convIdForPushTrace,
                backendId: msg.backendId,
                outcome: "merge_same_backendId"
            )
            return
        }
        if let idx = messages.firstIndex(where: { $0.id == msg.id }) {
            var next = messages
            next[idx] = msg
            next.sort { $0.timestamp < $1.timestamp }
            messages = next
            if msg.isOfferContent {
                mergeOffersFromMessages()
            }
            rebuildTimelineOrder()
            ChatPushTraceDebugState.shared.markSocketTraffic(conversationId: convIdForPushTrace, summary: "message_received_same_id")
            publishInboxPreviewFromMessage(msg)
            notifyInboxListShouldRefresh()
            scheduleDebouncedChatCatchUpFromServer()
            ChatThreadUIUpdateDebugState.shared.recordUIHandlerOutcome(
                conversationId: convIdForPushTrace,
                backendId: msg.backendId,
                outcome: "replace_same_message_id"
            )
            return
        }
        messages = (messages + [msg]).sorted { $0.timestamp < $1.timestamp }
        if msg.isOfferContent {
            mergeOffersFromMessages()
        }
        rebuildTimelineOrder()
        ChatPushTraceDebugState.shared.markSocketTraffic(conversationId: convIdForPushTrace, summary: "message_received")
        publishInboxPreviewFromMessage(msg)
        notifyInboxListShouldRefresh()
        scheduleDebouncedChatCatchUpFromServer()
        ChatThreadUIUpdateDebugState.shared.recordUIHandlerOutcome(
            conversationId: convIdForPushTrace,
            backendId: msg.backendId,
            outcome: "append_new_row"
        )
    }

    private func connectWebSocket() {
        guard displayedConversation.id != "0",
              let token = (authService.refreshToken ?? authService.authToken), !token.isEmpty else { return }
        reconnectTask?.cancel()
        reconnectTask = nil
        ChatPushTraceDebugState.shared.markSocketConnectAttempt(conversationId: displayedConversation.id)
        let convIdForPushTrace = displayedConversation.id
        let ws = ChatWebSocketService(conversationId: displayedConversation.id, token: token)
        let bridge = socketUIBridge
        ws.onNewMessage = { msg, echoMessageUuid in
            bridge.emitIncomingMessage(msg, echoMessageUuid, conversationId: convIdForPushTrace)
        }
        ws.onOfferEvent = { event in
            bridge.emitOffer(event)
        }
        ws.onOrderEvent = { event in
            bridge.emitOrder(event)
        }
        ws.onMessageReaction = { event in
            bridge.emitReaction(event)
        }
        let typingModel = remoteTypingIndicator
        let authForTyping = authService
        ws.onTypingEvent = { event in
            typingModel.handleSocketEvent(event, currentUsername: authForTyping.username)
            if event.isTyping {
                Task { @MainActor in
                    ChatPushTraceDebugState.shared.markSocketTraffic(conversationId: convIdForPushTrace, summary: "typing_from_peer")
                }
            }
        }
        ws.onConnectionStateChanged = { connected in
            Task { @MainActor in
                guard convIdForPushTrace != "0" else { return }
                if connected {
                    reconnectAttempt = 0
                    reconnectTask?.cancel()
                    reconnectTask = nil
                    ChatPushTraceDebugState.shared.markSocketConnected(conversationId: convIdForPushTrace)
                } else {
                    scheduleSocketReconnect(reason: "state_disconnected")
                }
            }
        }
        ws.onDisconnectReason = { reason in
            Task { @MainActor in
                guard convIdForPushTrace != "0" else { return }
                ChatPushTraceDebugState.shared.markSocketDisconnected(conversationId: convIdForPushTrace, reason: reason)
                // Transient URLSessionWebSocket send failures must not nil the client — that dropped the room and looked like "WS never pushes".
                if reason.hasPrefix("send_error:") {
                    return
                }
                webSocket = nil
                scheduleSocketReconnect(reason: reason)
            }
        }
        webSocket = ws
        ws.connect()
    }

    private func sendTypingForComposerChange(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            typingKeepaliveTask?.cancel()
            typingKeepaliveTask = nil
            if didSendTypingStart {
                webSocket?.sendTyping(isTyping: false)
                didSendTypingStart = false
            }
            return
        }
        // Notify immediately on first character — a 350ms debounce meant peers saw nothing until the user paused.
        if !didSendTypingStart {
            webSocket?.sendTyping(isTyping: true)
            didSendTypingStart = true
        }
        // Re-ping every ~2s while still composing so the other client’s 3s hide timer does not clear mid-paragraph.
        if typingKeepaliveTask == nil {
            typingKeepaliveTask = Task { @MainActor in
                defer { typingKeepaliveTask = nil }
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    guard !Task.isCancelled else { break }
                    let still = !newMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    if still, didSendTypingStart {
                        webSocket?.sendTyping(isTyping: true)
                    } else {
                        break
                    }
                }
            }
        }
    }

    private func loadMessages() {
        guard displayedConversation.id != "0" else {
            messages = []
            return
        }
        let convId = displayedConversation.id
        let hadCached = !messages.isEmpty
        if !hadCached {
            isLoading = true
        }
        Task {
            do {
                let msgs = try await chatService.getMessages(conversationId: convId)
                await MainActor.run {
                    guard displayedConversation.id == convId else { return }
                    let merged = self.mergedThreadMessages(server: msgs, local: self.messages)
                    self.messages = merged
                    self.cacheMessagesForConversation(merged, convId: convId)
                    self.isLoading = false
                    self.mergeOffersFromMessages()
                    self.rebuildTimelineOrder()
                }
                // Mark as read: messages from the other party (IDs we have from backend)
                let idsToMarkRead = msgs
                    .filter { !isCurrentUser(username: $0.senderUsername) }
                    .compactMap(\.backendId)
                if !idsToMarkRead.isEmpty {
                    _ = try? await chatService.readMessages(messageIds: idsToMarkRead)
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    // Don't wipe messages on error when we already have messages for this conversation (avoids empty chat on re-enter)
                    if displayedConversation.id != convId || messages.isEmpty {
                        self.messages = []
                    }
                    self.rebuildTimelineOrder()
                }
            }
        }
    }

    private func applyChatReaction(message: Message, emoji: String) {
        guard let username = authService.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { return }
        let convId = displayedConversation.id
        guard convId != "0" else { return }
        let key = ChatMessageReactionsStore.stableKey(for: message)
        let beforeMine = messageReactionsStore.reactionsByUsername(conversationId: convId, messageKey: key)[username]
        let removingSameEmoji = beforeMine == emoji
        ChatMessageReactionsStore.shared.applyReaction(
            conversationId: convId,
            messageKey: key,
            username: username,
            emoji: emoji
        )
        if !removingSameEmoji {
            chatReactionEmojiUsageStore.recordUse(emoji)
        }
        if let bid = message.backendId {
            let mine = ChatMessageReactionsStore.shared.reactionsByUsername(conversationId: convId, messageKey: key)[username]
            webSocket?.sendMessageReaction(messageId: bid, emoji: mine)
        }
    }

    /// Tap reaction chip on bubble: remove only if it is the current user’s emoji (same toggle rules as `applyReaction`).
    private func removeChatReactionIfMine(message: Message, emoji: String) {
        guard let username = authService.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else { return }
        let convId = displayedConversation.id
        guard convId != "0" else { return }
        let key = ChatMessageReactionsStore.stableKey(for: message)
        let map = ChatMessageReactionsStore.shared.reactionsByUsername(conversationId: convId, messageKey: key)
        guard let storedUser = map.keys.first(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == username.lowercased()
        }), map[storedUser] == emoji else { return }
        ChatMessageReactionsStore.shared.applyReaction(
            conversationId: convId,
            messageKey: key,
            username: storedUser,
            emoji: emoji
        )
        if let bid = message.backendId {
            let mine = ChatMessageReactionsStore.shared.reactionsByUsername(conversationId: convId, messageKey: key)[storedUser]
            webSocket?.sendMessageReaction(messageId: bid, emoji: mine)
        }
    }

    private func sendMessage() {
        let text = newMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, displayedConversation.id != "0" else { return }
        newMessage = ""
        if didSendTypingStart {
            webSocket?.sendTyping(isTyping: false)
            didSendTypingStart = false
        }
        let messageUUID = UUID().uuidString
        let optimistic = Message(
            id: UUID(uuidString: messageUUID) ?? UUID(),
            senderUsername: authService.username ?? "You",
            content: text,
            type: "text"
        )
        messages = (messages + [optimistic]).sorted { $0.timestamp < $1.timestamp }
        pendingMessageUUID = messageUUID
        rebuildTimelineOrder()
        publishInboxPreviewFromMessage(optimistic)
        if let ws = webSocket, ws.send(message: text, messageUUID: messageUUID) {
            // WebSocket path persists on the server and triggers push; GraphQL SendMessage would duplicate the row.
        } else {
            Task {
                do {
                    _ = try await chatService.sendMessage(conversationId: displayedConversation.id, message: text, messageUuid: messageUUID)
                    await MainActor.run {
                        pendingMessageUUID = nil
                        loadMessages()
                    }
                } catch {
                    await MainActor.run {
                        messages = messages.filter { $0.id.uuidString != messageUUID }
                        pendingMessageUUID = nil
                        rebuildTimelineOrder()
                    }
                }
            }
        }
        notifyInboxListShouldRefresh()
    }
}

// MARK: - Offer card (Flutter OfferFirstCard)

/// Offer card at top of chat when conversation has an offer. Shows offer line, status, and actions: Accept/Decline/Send new offer (seller, pending), Pay (buyer when accepted — whoever sent the offer), Send new offer (rejected).
struct OfferCardView: View {
    let offer: OfferInfo
    let currentUsername: String?
    let isSeller: Bool
    let isResponding: Bool
    let errorMessage: String?
    let onAccept: () async -> Void
    let onDecline: () async -> Void
    let onSendNewOffer: () -> Void
    let onPayNow: () -> Void
    /// When true, this card was superseded by a newer offer; show only offer line + status (no "Send new offer" button).
    var forceGreyedOut: Bool = false

    private var offerLine: String {
        let priceStr = CurrencyFormatter.gbp(offer.offerPrice)
        if offer.sentByCurrentUser {
            return "You offered \(priceStr)"
        }
        return "\(offer.buyer?.username ?? "They") offered \(priceStr)"
    }

    private var statusText: String {
        switch (offer.status ?? "").uppercased() {
        case "PENDING": return "Pending"
        case "ACCEPTED": return "Accepted"
        case "REJECTED", "CANCELLED": return "Declined"
        default: return offer.status ?? "Pending"
        }
    }

    private var statusColor: Color {
        switch (offer.status ?? "").uppercased() {
        case "PENDING": return Theme.Colors.secondaryText
        case "ACCEPTED": return .green
        case "REJECTED", "CANCELLED": return .red
        default: return Theme.Colors.secondaryText
        }
    }

    /// Hide status label when Pending or Countered (per design: don't show "COUNTERED" / "Pending" on cards).
    private var shouldShowStatus: Bool {
        let s = (offer.status ?? "").uppercased()
        return s != "PENDING" && s != "COUNTERED"
    }

    /// True when this offer was sent by the current user (sender sees only "Send new offer").
    private var isOfferSentByMe: Bool {
        offer.sentByCurrentUser
    }

    private var timestampLabel: String {
        offer.createdAt.map { Self.relativeTimestamp(for: $0) } ?? "—"
    }

    /// Same relative format as message bubbles (e.g. "Just now", "9 mins ago").
    private static func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        if now.timeIntervalSince(date) < 60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let str = formatter.localizedString(for: date, relativeTo: now)
        if str.hasPrefix("in ") { return "Just now" }
        return str
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(offerLine)
                .font(Theme.Typography.body)
                .fontWeight(.semibold)
                .foregroundColor(Theme.Colors.primaryText)
            if shouldShowStatus {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                    Text(statusText)
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(statusColor)
                    Spacer(minLength: 0)
                    Text(timestampLabel)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            } else {
                HStack {
                    Spacer(minLength: 0)
                    Text(timestampLabel)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            if let err = errorMessage, !err.isEmpty {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(.red)
            }

            // Button logic: evaluate **accepted** before "I sent" so buyers who sent the accepted offer see Pay, not "Send new offer".
            if forceGreyedOut {
                EmptyView()
            }
            // CASE 1: Accepted → purchaser (not listing seller / accepter) pays, regardless of who sent that offer.
            else if offer.isAccepted {
                VStack(spacing: Theme.Spacing.sm) {
                    if !isSeller {
                        Button(action: onPayNow) {
                            Text("Pay")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .background(Theme.primaryColor)
                                .foregroundColor(.white)
                                .cornerRadius(22)
                        }
                        .disabled(isResponding)
                    }

                    // For both sides: accepted offers still allow starting a new offer.
                    Button(action: onSendNewOffer) {
                        Text("Send new offer")
                            .font(.system(size: 15, weight: .regular))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.primaryColor, lineWidth: 1))
                            .foregroundColor(Theme.primaryColor)
                            .cornerRadius(22)
                    }
                    .disabled(isResponding)
                }
            }
            // CASE 2: I sent a pending offer → only "Send new offer"
            else if isOfferSentByMe {
                Button(action: onSendNewOffer) {
                    Text("Send new offer")
                        .font(.system(size: 15, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.primaryColor, lineWidth: 1))
                        .foregroundColor(Theme.Colors.primaryText)
                        .cornerRadius(22)
                }
                .disabled(isResponding)
            }
            // CASE 3: I received an offer (pending) → Accept / Decline / Send new offer
            else if !isOfferSentByMe && !offer.isRejected {
                VStack(spacing: Theme.Spacing.sm) {
                    Button(action: { Task { await onAccept() } }) {
                        Text("Accept")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Theme.primaryColor)
                            .foregroundColor(.white)
                            .cornerRadius(22)
                    }
                    .disabled(isResponding)
                    HStack(spacing: Theme.Spacing.sm) {
                        Button(action: { Task { await onDecline() } }) {
                            Text("Decline")
                                .font(.system(size: 15, weight: .regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.primaryColor, lineWidth: 1))
                                .foregroundColor(Theme.Colors.primaryText)
                                .cornerRadius(22)
                        }
                        .disabled(isResponding)
                        Button(action: onSendNewOffer) {
                            Text("Send new offer")
                                .font(.system(size: 15, weight: .regular))
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.primaryColor, lineWidth: 1))
                                .foregroundColor(Theme.Colors.primaryText)
                                .cornerRadius(22)
                        }
                        .disabled(isResponding)
                    }
                }
            }
            // CASE 4: Rejected → both can send new offer
            else if offer.isRejected {
                Button(action: onSendNewOffer) {
                    Text("Send new offer")
                        .font(.system(size: 15, weight: .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.primaryColor, lineWidth: 1))
                        .foregroundColor(Theme.Colors.primaryText)
                        .cornerRadius(22)
                }
                .disabled(isResponding)
            }

            if isResponding {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }
}

/// Product card shown at top of chat when conversation was started from product detail (Flutter ProductCard).
struct ChatProductCardView: View {
    let item: Item

    /// Prefer live URLs on `item`, then last persisted header URL for this product (same store as offer/order headers).
    private var displayImageURLString: String? {
        if let s = item.thumbnailURLForChrome?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        guard let pid = item.productId.flatMap({ Int($0) }) else { return nil }
        return ChatHeaderProductImageURLStore.url(forProductId: pid)
    }

    var body: some View {
        NavigationLink(destination: ItemDetailView(item: item)) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Group {
                    if let urlString = displayImageURLString, let url = URL(string: urlString) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Rectangle()
                                    .fill(Theme.Colors.secondaryBackground)
                                    .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                            @unknown default:
                                EmptyView()
                            }
                        }
                    } else {
                        Rectangle()
                            .fill(Theme.Colors.secondaryBackground)
                            .overlay(Image(systemName: "photo").foregroundColor(Theme.Colors.secondaryText))
                    }
                }
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(item.formattedPrice)
                        .font(Theme.Typography.body)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14))
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, ChatThreadLayout.horizontalGutter)
            .padding(.vertical, Theme.Spacing.sm)
        }
        .buttonStyle(PlainTappableButtonStyle())
    }
}

/// Order/offer header thumbnail: shows a spinner while the URL is missing or the image is loading (avoids shimmer placeholder flash).
private struct ChatHeaderProductThumbnail: View {
    var imageURL: URL?
    /// Non-empty image string from API that did not parse as a URL — show photo placeholder, not an endless spinner.
    var invalidURLFromAPI: Bool = false
    var soldOverlayActive: Bool = false

    var body: some View {
        Group {
            if invalidURLFromAPI {
                thumbnailUnavailable
            } else if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        thumbnailUnavailable
                    default:
                        thumbnailLoading
                    }
                }
            } else {
                thumbnailLoading
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: 56, height: 56)
        .saturation(soldOverlayActive ? 0 : 1)
        .overlay {
            if soldOverlayActive {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.35))
            }
        }
        .clipped()
        .cornerRadius(8)
    }

    private var thumbnailLoading: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.secondaryBackground)
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Theme.primaryColor)
        }
    }

    private var thumbnailUnavailable: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.secondaryBackground)
            Image(systemName: "photo")
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }
}

/// Order confirmation card shown in timeline when conversation has an order (sale details). Includes timestamp for chronological ordering.
struct OrderConfirmationCardView: View {
    let order: ConversationOrder
    let isSeller: Bool

    private static func orderStatusDisplay(_ status: String) -> String {
        switch status {
        case "CONFIRMED": return "Confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED": return "Cancelled"
        case "REFUNDED": return "Refunded"
        default: return status
        }
    }

    private static func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let str = formatter.localizedString(for: date, relativeTo: now)
        if str.hasPrefix("in ") { return "Just now" }
        return str
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(Theme.primaryColor)
                Text(isSeller ? "Item sold" : "Order confirmed")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
            }
            HStack {
                Text(CurrencyFormatter.gbp(order.total))
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(Theme.primaryColor)
                Text("•")
                    .foregroundColor(Theme.Colors.secondaryText)
                Text(Self.orderStatusDisplay(order.status))
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            if let name = order.firstProductName, !name.isEmpty {
                Text(name)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .lineLimit(2)
            }
            NavigationLink(destination: OrderHelpView(orderId: order.id, conversationId: "")) {
                Text("Report an issue")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.primaryColor)
            }
            .buttonStyle(PlainTappableButtonStyle())
            HStack {
                Spacer(minLength: 0)
                Text(order.createdAt.map { Self.relativeTimestamp(for: $0) } ?? "—")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Theme.Colors.glassBorder, lineWidth: 1)
        )
    }
}

/// Animated primary-gradient border used for the sale banner.
private struct AnimatedPrimaryGradientBorder: View {
    let cornerRadius: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Slow but clearly visible rotation. Loops forever.
            let angle = Angle(degrees: (t * 25).truncatingRemainder(dividingBy: 360))
            let gradient = AngularGradient(
                gradient: Gradient(colors: [
                    Theme.primaryColor.opacity(0.10),
                    Theme.primaryColor.opacity(0.95),
                    Theme.primaryColor.opacity(0.35),
                    Theme.primaryColor.opacity(0.10),
                ]),
                center: .center,
                angle: angle
            )

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))

                // Soft glow so the card reads as "sale" rather than "offer".
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(gradient.opacity(0.45), style: StrokeStyle(lineWidth: lineWidth + 2.5, lineCap: .round, lineJoin: .round))
                    .blur(radius: 6)
                    .opacity(0.9)
            }
        }
    }
}

/// Slowly drifts a primary-tinted gradient horizontally (left to right).
private struct AnimatedPrimaryHorizontalFill: View {
    let cornerRadius: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            // Smooth left-to-right drift that loops forever.
            let p = (t * 0.05).truncatingRemainder(dividingBy: 1) // [0,1)
            let xCenter = CGFloat(p) * 0.8 + 0.1 // [0.1,0.9]

            let start = UnitPoint(x: xCenter - 0.30, y: 0.0)
            let end = UnitPoint(x: xCenter + 0.30, y: 1.0)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Theme.primaryColor.opacity(0.22),
                            Theme.primaryColor.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: start,
                        endPoint: end
                    )
                )
        }
    }
}

/// Sold event card in timeline: "You bought this for £X" / "X bought this for £X".
struct SoldConfirmationCardView: View {
    let order: OrderInfo
    let currentUsername: String?
    var conversationId: String? = nil
    var detailOrder: Order? = nil
    var isSellerView: Bool? = nil
    var onOrderChanged: (() -> Void)? = nil
    @EnvironmentObject var authService: AuthService
    @State private var showBuyerHelp = false
    @State private var showSellerOptions = false
    @State private var showOrderDetails = false

    private var isBuyer: Bool {
        currentUsername.map {
            order.buyerUsername.trimmingCharacters(in: .whitespaces).lowercased() ==
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        } ?? false
    }

    private var isSeller: Bool {
        currentUsername.map {
            order.sellerUsername.trimmingCharacters(in: .whitespaces).lowercased() ==
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        } ?? false
    }

    private static func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let str = formatter.localizedString(for: date, relativeTo: now)
        if str.hasPrefix("in ") { return "Just now" }
        return str
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                ZStack {
                    Circle()
                        .fill(Theme.primaryColor.opacity(0.12))
                        .frame(width: 42, height: 42)
                    Circle()
                        .stroke(Theme.primaryColor.opacity(0.25), lineWidth: 1)
                        .frame(width: 42, height: 42)
                    Image(systemName: "shippingbox")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Theme.primaryColor, Theme.primaryColor.opacity(0.55)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                if order.rolesConfirmed {
                    Text(
                        isSeller
                            ? "This item has sold"
                            : (isBuyer ? "Payment successful!" : "\(order.buyerUsername) bought this")
                    )
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                } else {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(Theme.primaryColor)
                    Text("Loading…")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            HStack {
                Button(action: {
                    if isSeller {
                        showSellerOptions = true
                    } else {
                        showBuyerHelp = true
                    }
                }) {
                    Text("I have a problem")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .buttonStyle(PlainTappableButtonStyle())
                .disabled(!order.rolesConfirmed)
                Spacer(minLength: Theme.Spacing.sm)
                Text(Self.relativeTimestamp(for: order.createdAt))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack(alignment: .topLeading) {
                Theme.Colors.secondaryBackground
                AnimatedPrimaryHorizontalFill(cornerRadius: 24)
                    .opacity(0.85)
            }
        )
        .cornerRadius(24)
        .overlay {
            AnimatedPrimaryGradientBorder(cornerRadius: 24, lineWidth: 2)
        }
        .overlay(alignment: .topTrailing) {
            // Small sparkle accent so this card feels different from the plain offer cards.
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.primaryColor.opacity(0.95), Theme.primaryColor.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .padding(Theme.Spacing.md)
                .opacity(order.rolesConfirmed ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard order.rolesConfirmed, detailOrder != nil else { return }
            showOrderDetails = true
        }
        .background(
            Group {
                NavigationLink(
                    destination: OrderHelpView(orderId: order.orderId, conversationId: conversationId),
                    isActive: $showBuyerHelp
                ) { EmptyView() }
                .hidden()
                if let detailOrder {
                    NavigationLink(
                        destination: OrderDetailView(order: detailOrder, isSeller: isSellerView ?? isSeller),
                        isActive: $showOrderDetails
                    ) { EmptyView() }
                    .hidden()
                }
            }
        )
        .sheet(isPresented: $showSellerOptions) {
            NavigationStack {
                SellerOrderProblemOptionsView(orderId: order.orderId) {
                    showSellerOptions = false
                    onOrderChanged?()
                }
                .environmentObject(authService)
            }
        }
    }
}

// MARK: - Order cancellation chat cards (buyer/seller request + outcome)

private struct OrderCancellationRequestChatCardView: View {
    let message: Message
    let payload: (orderId: Int, requestedBySeller: Bool, status: String)
    /// Backend keeps request JSON as PENDING and appends a separate outcome message; hide actions once that exists.
    let resolvedByLaterOutcome: Bool
    /// Used with `message.senderUsername`: backend sets message sender to whoever initiated the cancellation.
    let currentUsername: String?
    /// If `senderUsername` is missing, infer initiator from offer seller vs buyer the old way.
    let isSellerRoleFallback: Bool
    var onFinished: () -> Void

    @EnvironmentObject var authService: AuthService
    @State private var busy = false
    @State private var err: String?
    private let userService = UserService()

    private var initiatorIsCurrentUser: Bool {
        let a = message.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let b = (currentUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !a.isEmpty, !b.isEmpty { return a == b }
        if payload.requestedBySeller { return isSellerRoleFallback }
        return !isSellerRoleFallback
    }

    private var statusAllowsAction: Bool {
        let s = payload.status.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s == "PENDING"
    }

    private var canRespond: Bool {
        guard !resolvedByLaterOutcome, statusAllowsAction else { return false }
        return !initiatorIsCurrentUser
    }

    private var title: String {
        if initiatorIsCurrentUser {
            return "You asked to cancel this order"
        }
        if payload.requestedBySeller {
            return "The seller asked to cancel this order"
        }
        return "The buyer asked to cancel this order"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Title on its own row (full width); time on the next row, trailing — avoids wrapping around a top-right timestamp.
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer(minLength: 0)
                    Text(message.formattedTimestamp)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            if canRespond {
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        Task { await respond(approve: false) }
                    } label: {
                        Text("Decline")
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.Colors.tertiaryBackground)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                    Button {
                        Task { await respond(approve: true) }
                    } label: {
                        Text("Approve")
                            .font(Theme.Typography.body)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(Theme.primaryColor)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
                .disabled(busy)
            } else if statusAllowsAction, !resolvedByLaterOutcome, initiatorIsCurrentUser {
                Text("Waiting for the other party.")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            if busy {
                ProgressView()
            }
            if let err, !err.isEmpty {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
    }

    private func respond(approve: Bool) async {
        await MainActor.run {
            busy = true
            err = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            if approve {
                try await userService.approveOrderCancellation(orderId: payload.orderId)
            } else {
                try await userService.rejectOrderCancellation(orderId: payload.orderId)
            }
            await MainActor.run {
                busy = false
                onFinished()
            }
        } catch {
            await MainActor.run {
                busy = false
                err = error.localizedDescription
            }
        }
    }
}

private struct OrderCancellationOutcomeChatCardView: View {
    let message: Message

    private var approved: Bool {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["type"] as? String) == "order_cancellation_outcome" else { return false }
        return (json["approved"] as? Bool) ?? false
    }

    var body: some View {
        Text(approved ? "Order cancellation was approved." : "Order cancellation was declined.")
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.secondaryText)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
    }
}

/// Seller-side problem actions from sold confirmation banner.
private struct SellerOrderProblemOptionsView: View {
    let orderId: String
    var onOrderChanged: (() -> Void)? = nil
    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var showCancelConfirm = false
    @State private var isCancelling = false
    @State private var errorMessage: String?
    private let userService = UserService()

    var body: some View {
        List {
            Section("Need help with this sale?") {
                NavigationLink("Order status issue") { HelpChatView() }
                NavigationLink("Delivery / collection issue") { HelpChatView() }
                NavigationLink("Payment issue") { HelpChatView() }
            }
            Section("Order actions") {
                Button(role: .destructive) { showCancelConfirm = true } label: {
                    if isCancelling {
                        ProgressView()
                    } else {
                        Text("Cancel order")
                    }
                }
                .disabled(isCancelling)
            }
            if let err = errorMessage, !err.isEmpty {
                Section {
                    Text(err)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Order issue options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .alert("Cancel this order?", isPresented: $showCancelConfirm) {
            Button("Keep order", role: .cancel) { }
            Button("Cancel order", role: .destructive) {
                Task { await cancelOrder() }
            }
        } message: {
            Text("This will request cancellation for this order.")
        }
    }

    private func cancelOrder() async {
        guard let oid = Int(orderId) else {
            await MainActor.run { errorMessage = "Invalid order id" }
            return
        }
        await MainActor.run { isCancelling = true; errorMessage = nil }
        userService.updateAuthToken(authService.authToken)
        do {
            try await userService.sellerRequestOrderCancellation(
                orderId: oid,
                reason: "CHANGED_MY_MIND",
                notes: "Seller requested cancellation from chat sold banner.",
                imagesUrl: []
            )
            await MainActor.run {
                isCancelling = false
                onOrderChanged?()
                dismiss()
            }
        } catch {
            await MainActor.run {
                isCancelling = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OrderIssueChatCardView: View {
    let message: Message
    var currentUsername: String?

    private static func relativeTimestamp(for date: Date) -> String {
        let now = Date()
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let str = formatter.localizedString(for: date, relativeTo: now)
        if str.hasPrefix("in ") { return "Just now" }
        return str
    }

    var body: some View {
        let payload = message.parsedOrderIssueDetails
        let sender = message.senderUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let me = (currentUsername ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let titleText: String = {
            guard !sender.isEmpty, !me.isEmpty else { return "Order issue reported" }
            if sender == me { return "You reported an issue" }
            return "\(message.senderUsername) reported an issue"
        }()
        NavigationLink(destination: OrderIssueDetailView(issueId: payload?.issueId, publicId: payload?.publicId)) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(titleText)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                if let rawType = payload?.issueType, !rawType.isEmpty {
                    Text(humanReadableIssueType(rawType))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                if let details = payload?.description,
                   !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(details)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.primaryText)
                }
                if let urls = payload?.imageUrls, !urls.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(urls, id: \.self) { urlString in
                                if let url = URL(string: urlString) {
                                    AsyncImage(url: url) { phase in
                                        switch phase {
                                        case .success(let image):
                                            image.resizable().scaledToFill()
                                        default:
                                            Rectangle().fill(Theme.Colors.tertiaryBackground)
                                        }
                                    }
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                    Text("Order on hold")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer(minLength: 0)
                    Text(Self.relativeTimestamp(for: message.timestamp))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Colors.secondaryBackground)
            .cornerRadius(24)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Theme.Colors.glassBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainTappableButtonStyle())
    }

    private func humanReadableIssueType(_ raw: String) -> String {
        switch raw {
        case "NOT_AS_DESCRIBED": return "Item not as described"
        case "TOO_SMALL": return "Item is too small"
        case "COUNTERFEIT": return "Item is counterfeit"
        case "DAMAGED": return "Item is damaged or broken"
        case "WRONG_COLOR": return "Item is wrong colour"
        case "WRONG_SIZE": return "Item is wrong size"
        case "DEFECTIVE": return "Item doesn't work / defective"
        case "OTHER": return "Other"
        default: return raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct TypingDotsView: View {
    @State private var animate = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .frame(width: 5, height: 5)
                .scaleEffect(animate ? 1.0 : 0.6)
                .opacity(animate ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.55).repeatForever().delay(0.0), value: animate)
            Circle()
                .frame(width: 5, height: 5)
                .scaleEffect(animate ? 1.0 : 0.6)
                .opacity(animate ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.55).repeatForever().delay(0.12), value: animate)
            Circle()
                .frame(width: 5, height: 5)
                .scaleEffect(animate ? 1.0 : 0.6)
                .opacity(animate ? 1.0 : 0.45)
                .animation(.easeInOut(duration: 0.55).repeatForever().delay(0.24), value: animate)
        }
        .foregroundColor(Theme.Colors.secondaryText)
        .onAppear { animate = true }
    }
}

struct MessageBubbleView: View {
    let message: Message
    let isCurrentUser: Bool
    /// When true and not current user, show avatar to the left of the bubble (first in group).
    var showAvatar: Bool = false
    /// When true, show timestamp below the bubble (only on last message of a group to avoid repetition).
    var showTimestamp: Bool = true
    var avatarURL: String? = nil
    var recipientUsername: String = ""
    /// Shown only for the **last** message you sent when the other participant has read it (single label for the thread).
    var showSeenLabel: Bool = false
    /// Local reaction counts (username → emoji); same model as WhatsApp aggregates.
    var reactionsByUsername: [String: String] = [:]
    /// Long-press to open WhatsApp-style reaction tray; nil disables the gesture.
    var onLongPress: (() -> Void)? = nil
    /// Double-tap the bubble to toggle ❤️ (nil disables).
    var onDoubleTapHeart: (() -> Void)? = nil
    /// Single-tap the bubble to show/hide this row’s timestamp (nil disables; uses ExclusiveGesture with double-tap when both set).
    var onToggleTimestampVisibility: (() -> Void)? = nil
    /// Tap the chip that matches the current user’s reaction to remove it (nil = not interactive).
    var onTapMyReactionChip: ((String) -> Void)? = nil
    /// Matched case-insensitively to `reactionsByUsername` keys for tap-to-remove.
    var currentUsernameForReactions: String? = nil
    /// Slight scale while the reaction overlay targets this bubble.
    var isReactionTargeted: Bool = false

    private var bubbleMaxWidth: CGFloat { UIScreen.main.bounds.width * 0.78 }
    private var baseMessageFontSize: CGFloat { 17 }
    private static let messageAvatarSize: CGFloat = 28
    /// Half of former `lg` so sent/received rows sit closer to screen edges (matches tighter `ChatThreadLayout.horizontalGutter`).
    private static let bubbleSideSpacerMin: CGFloat = Theme.Spacing.lg / 2
    /// Vertical offset so the avatar is centered with a single-line bubble. This position is kept for multi-line bubbles (avatar does not re-center).
    private static let avatarTopOffsetForSingleLineCenter: CGFloat = 4

    @ViewBuilder
    private var messageAvatarView: some View {
        if PreluraSupportBranding.isSupportRecipient(username: recipientUsername) {
            PreluraSupportBranding.supportAvatar(size: Self.messageAvatarSize)
        } else {
            Group {
                if let u = avatarURL, !u.isEmpty, let url = URL(string: u) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        default: messageAvatarPlaceholder
                        }
                    }
                } else {
                    messageAvatarPlaceholder
                }
            }
            .frame(width: Self.messageAvatarSize, height: Self.messageAvatarSize)
            .clipShape(Circle())
        }
    }

    private var messageAvatarPlaceholder: some View {
        Circle()
            .fill(Theme.Colors.tertiaryBackground)
            .overlay(
                Text(String((recipientUsername.isEmpty ? "?" : recipientUsername).prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.Colors.secondaryText)
            )
    }

    /// Reactions from the signed-in user vs everyone else (for corner placement on the bubble).
    private var reactionsPartitioned: (mine: [String: String], others: [String: String]) {
        guard let me = currentUsernameForReactions?.trimmingCharacters(in: .whitespacesAndNewlines), !me.isEmpty else {
            return ([:], reactionsByUsername.filter { !$0.value.isEmpty })
        }
        let lower = me.lowercased()
        var mine: [String: String] = [:]
        var others: [String: String] = [:]
        for (u, e) in reactionsByUsername where !e.isEmpty {
            if u.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower {
                mine[u] = e
            } else {
                others[u] = e
            }
        }
        return (mine, others)
    }

    private var hasAnyReaction: Bool {
        reactionsByUsername.values.contains { !$0.isEmpty }
    }

    private static let reactionOverlayOffsetX: CGFloat = 6
    private static let reactionOverlayOffsetY: CGFloat = 10

    @ViewBuilder
    private func reactionClusterRow(for map: [String: String]) -> some View {
        let nonEmpty = map.filter { !$0.value.isEmpty }
        if nonEmpty.isEmpty {
            EmptyView()
        } else {
            let byEmoji = Dictionary(grouping: nonEmpty.values, by: { $0 })
            let sortedEmojis = byEmoji.keys.sorted()
            HStack(spacing: 4) {
                ForEach(sortedEmojis, id: \.self) { em in
                    let count = byEmoji[em]?.count ?? 0
                    let myEm = myReactionEmoji(in: map)
                    let canTapRemoveMine = onTapMyReactionChip != nil && myEm == em
                    reactionChip(emoji: em, count: count, showRemoveHint: canTapRemoveMine) {
                        guard canTapRemoveMine else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onTapMyReactionChip?(em)
                    }
                }
            }
        }
    }

    private func myReactionEmoji(in map: [String: String]) -> String? {
        guard let me = currentUsernameForReactions?.trimmingCharacters(in: .whitespacesAndNewlines), !me.isEmpty else { return nil }
        let lower = me.lowercased()
        for (u, e) in map where !e.isEmpty {
            if u.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == lower { return e }
        }
        return nil
    }

    @ViewBuilder
    private func reactionChip(emoji: String, count: Int, showRemoveHint: Bool, action: @escaping () -> Void) -> some View {
        let label = HStack(spacing: 3) {
            Text(emoji)
                .font(.system(size: 15))
            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Theme.Colors.secondaryBackground.opacity(0.96))
        )
        if showRemoveHint {
            Button(action: action) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Remove reaction"))
        } else {
            label
        }
    }

    /// Text bubble + rounded background (non–emoji-only).
    @ViewBuilder
    private func standardBubbleLabel(_ bubbleText: String) -> some View {
        Text(bubbleText)
            .font(Theme.Typography.body)
            .foregroundColor(isCurrentUser ? .white : Theme.Colors.primaryText)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                isCurrentUser
                    ? LinearGradient(
                        colors: [Theme.primaryColor, Theme.primaryColor.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [Theme.Colors.secondaryBackground, Theme.Colors.secondaryBackground],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
            )
            .cornerRadius(18)
    }

    /// Bubble content with reactions on top corners: others → top-leading, yours → top-trailing.
    @ViewBuilder
    private func bubbleWithCornerReactions(
        emojiMult: Double?,
        bubbleText: String
    ) -> some View {
        let parts = reactionsPartitioned
        let hasOthers = !parts.others.isEmpty
        let hasMine = !parts.mine.isEmpty

        ZStack(alignment: .topLeading) {
            Group {
                if let mult = emojiMult {
                    Text(message.content.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: baseMessageFontSize * CGFloat(mult)))
                        .foregroundColor(isCurrentUser ? Theme.primaryColor : Theme.Colors.primaryText)
                        .multilineTextAlignment(isCurrentUser ? .trailing : .leading)
                } else {
                    standardBubbleLabel(bubbleText)
                }
            }
            if hasOthers {
                reactionClusterRow(for: parts.others)
                    .offset(x: -Self.reactionOverlayOffsetX, y: -Self.reactionOverlayOffsetY)
            }
        }
        .overlay(alignment: .topTrailing) {
            if hasMine {
                reactionClusterRow(for: parts.mine)
                    .offset(x: Self.reactionOverlayOffsetX, y: -Self.reactionOverlayOffsetY)
            }
        }
        .frame(maxWidth: emojiMult != nil ? .infinity : bubbleMaxWidth, alignment: isCurrentUser ? .trailing : .leading)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: ChatBubbleFramePreferenceKey.self,
                    value: [message.id: geo.frame(in: .global)]
                )
            }
        )
    }

    @ViewBuilder
    private func bubbleWithTapGestures(emojiMult: Double?, bubbleText: String) -> some View {
        let padded = bubbleWithCornerReactions(emojiMult: emojiMult, bubbleText: bubbleText)
            .padding(.top, hasAnyReaction ? 12 : 0)
        if onDoubleTapHeart != nil, onToggleTimestampVisibility != nil {
            padded.gesture(
                ExclusiveGesture(
                    TapGesture(count: 2).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onDoubleTapHeart?()
                    },
                    TapGesture(count: 1).onEnded { _ in
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onToggleTimestampVisibility?()
                    }
                )
            )
        } else if onDoubleTapHeart != nil {
            padded.simultaneousGesture(
                TapGesture(count: 2).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onDoubleTapHeart?()
                }
            )
        } else if onToggleTimestampVisibility != nil {
            padded.onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onToggleTimestampVisibility?()
            }
        } else {
            padded
        }
    }

    var body: some View {
        let emojiMult = message.emojiOnlyScaleMultiplier
        let bubbleText = message.displayContentForBubble(isFromCurrentUser: isCurrentUser)

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: Theme.Spacing.xs) {
                if isCurrentUser { Spacer(minLength: Self.bubbleSideSpacerMin) }
                if !isCurrentUser {
                    Group {
                        if showAvatar {
                            messageAvatarView
                                .offset(y: Self.avatarTopOffsetForSingleLineCenter)
                        } else {
                            Color.clear
                                .frame(width: Self.messageAvatarSize, height: Self.messageAvatarSize)
                        }
                    }
                }
                bubbleWithTapGestures(emojiMult: emojiMult, bubbleText: bubbleText)
                if !isCurrentUser { Spacer(minLength: Self.bubbleSideSpacerMin) }
            }
            if showTimestamp {
                HStack {
                    if isCurrentUser { Spacer(minLength: 0) }
                    Text(message.formattedTimestamp)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.leading, isCurrentUser ? 0 : (Self.messageAvatarSize + Theme.Spacing.xs))
            }
            if showSeenLabel {
                HStack {
                    Spacer(minLength: 0)
                    Text(L10n.string("Seen"))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.leading, isCurrentUser ? 0 : (Self.messageAvatarSize + Theme.Spacing.xs))
            }
        }
        .padding(.vertical, 2)
        .scaleEffect(isReactionTargeted ? 1.045 : 1.0)
        .animation(.spring(response: 0.34, dampingFraction: 0.72), value: isReactionTargeted)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: onLongPress == nil ? 999 : 0.45)
                .onEnded { _ in
                    guard let onLongPress else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onLongPress()
                }
        )
    }
}

#Preview {
    NavigationView {
        ChatDetailView(conversation: Conversation(
            id: "1",
            recipient: User.sampleUser,
            lastMessage: "Hello!",
            lastMessageTime: Date(),
            unreadCount: 0
        ))
    }
    .preferredColorScheme(.dark)
}
