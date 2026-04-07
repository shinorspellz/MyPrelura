import SwiftUI

/// Inbox filter from Messages 3-dot menu.
private enum InboxFilter: String, CaseIterable {
    case all = "All"
    case unread = "Unread"
    case read = "Read"
    case archived = "Archive"

    var localizedTitle: String {
        switch self {
        case .all: return L10n.string("All")
        case .unread: return L10n.string("Unread")
        case .read: return L10n.string("Read")
        case .archived: return L10n.string("Archive")
        }
    }
}

struct ChatListView: View {
    @EnvironmentObject var authService: AuthService
    @ObservedObject var tabCoordinator: TabCoordinator
    @ObservedObject var inboxViewModel: InboxViewModel
    @Binding var path: [AppRoute]
    @State private var searchText: String = ""
    @State private var scrollPosition: String? = "inbox_top"
    /// Inbox filter from 3-dot menu: all, unread, read, archived.
    @State private var inboxFilter: InboxFilter = .all
    /// Shown after swipe-archive; auto-dismisses after a few seconds unless the user taps Undo.
    @State private var archiveUndoConversation: Conversation?
    @State private var archiveUndoDismissTask: Task<Void, Never>?

    private var conversations: [Conversation] { inboxViewModel.conversations }
    private var archivedConversations: [Conversation] { inboxViewModel.archivedConversations }
    private var isLoading: Bool { inboxViewModel.isLoading }
    private var errorMessage: String? { inboxViewModel.errorMessage }
    /// No rows from either inbox query (used for first-load shimmer and empty state).
    private var hasNoInboxData: Bool { conversations.isEmpty && archivedConversations.isEmpty }

    init(tabCoordinator: TabCoordinator, path: Binding<[AppRoute]>, inboxViewModel: InboxViewModel) {
        self.tabCoordinator = tabCoordinator
        _path = path
        self.inboxViewModel = inboxViewModel
    }
    
    var body: some View {
        Group {
            if authService.isGuestMode {
                GuestSignInPromptView()
                    .navigationTitle(L10n.string("Messages"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            } else if isLoading && hasNoInboxData {
                InboxShimmerView()
                    .navigationBarHidden(true)
            } else if !isLoading && filteredConversations.isEmpty && (errorMessage != nil || hasNoInboxData) {
                ZStack(alignment: .bottom) {
                    VStack(spacing: Theme.Spacing.lg) {
                        Image(systemName: errorMessage != nil ? "exclamationmark.triangle" : "message")
                            .font(.system(size: 60))
                            .foregroundColor(errorMessage != nil ? Theme.primaryColor : Theme.Colors.secondaryText)
                        Text(errorMessage != nil ? "Couldn't load conversations" : "No conversations yet")
                            .font(Theme.Typography.title3)
                            .foregroundColor(Theme.Colors.primaryText)
                            .multilineTextAlignment(.center)
                        if let error = errorMessage, !error.isEmpty {
                            Text(error)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .padding(.horizontal)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.Colors.background)
                    .padding(.bottom, errorMessage != nil ? 100 : 0)

                    if errorMessage != nil {
                        PrimaryButtonBar {
                            PrimaryGlassButton("Retry", action: {
                                inboxViewModel.errorMessage = nil
                                inboxViewModel.refresh()
                            })
                        }
                    }
                }
                .navigationTitle(L10n.string("Messages"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Theme.Colors.background, for: .navigationBar)
            } else {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        DiscoverSearchField(
                            text: $searchText,
                            placeholder: L10n.string("Search conversations"),
                            topPadding: Theme.Spacing.xs
                        )

                        List {
                            ForEach(Array(filteredConversations.enumerated()), id: \.element.id) { index, conversation in
                                Button(action: {
                                    path.append(AppRoute.conversation(conversation, isArchived: inboxFilter == .archived))
                                }) {
                                    ChatRowView(
                                        conversation: conversation,
                                        currentUsername: authService.username,
                                        isPeerTyping: inboxViewModel.peerTypingConversationIds.contains(conversation.id)
                                    )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(PlainTappableButtonStyle())
                                .id(index == 0 ? "inbox_top" : conversation.id)
                                .listRowBackground(Theme.Colors.background)
                                .listRowInsets(EdgeInsets(top: 8, leading: Theme.Spacing.md, bottom: 8, trailing: Theme.Spacing.md))
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    if inboxFilter == .archived {
                                        Button {
                                            unarchiveConversation(conversation)
                                        } label: {
                                            Label(L10n.string("Unarchive"), systemImage: "tray.and.arrow.up")
                                        }
                                        .tint(Theme.primaryColor)
                                    } else {
                                        Button {
                                            archiveConversation(conversation)
                                        } label: {
                                            Label(L10n.string("Archive"), systemImage: "archivebox")
                                        }
                                        .tint(.orange)
                                    }
                                }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .navigationLinkIndicatorVisibility(.hidden)
                        .scrollPosition(id: $scrollPosition, anchor: .top)
                        .onAppear {
                            tabCoordinator.reportAtTop(tab: 3, isAtTop: filteredConversations.isEmpty || scrollPosition == "inbox_top")
                            tabCoordinator.registerScrollToTop(tab: 3) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    proxy.scrollTo("inbox_top", anchor: .top)
                                }
                            }
                            tabCoordinator.registerRefresh(tab: 3) {
                                Task { await loadInboxConversations() }
                            }
                        }
                    }
                    .background(Theme.Colors.background)
                    .navigationTitle(L10n.string("Messages"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(Theme.Colors.background, for: .navigationBar)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Menu {
                                ForEach(InboxFilter.allCases, id: \.self) { filter in
                                    Button {
                                        inboxFilter = filter
                                    } label: {
                                        HStack {
                                            Text(filter.localizedTitle)
                                            Spacer(minLength: Theme.Spacing.md)
                                            if inboxFilter == filter {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 17, weight: .regular))
                                    .foregroundColor(Theme.Colors.primaryText)
                            }
                        }
                    }
                    .refreshable {
                        await loadInboxConversations()
                    }
                    .overlay(alignment: .bottom) {
                        if archiveUndoConversation != nil {
                            ArchiveUndoToast(onUndo: undoLastArchiveSwipe)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.bottom, 88)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.spring(response: 0.38, dampingFraction: 0.86), value: archiveUndoConversation?.id)
                }
                .onChange(of: scrollPosition) { _, new in
                    tabCoordinator.reportAtTop(tab: 3, isAtTop: new == "inbox_top")
                }
                .onChange(of: filteredConversations.isEmpty) { _, isEmpty in
                    if isEmpty { tabCoordinator.reportAtTop(tab: 3, isAtTop: true) }
                }
            }
        }
        .onAppear {
            tabCoordinator.reportAtTop(tab: 3, isAtTop: true)
            tabCoordinator.registerScrollToTop(tab: 3) { }
            tabCoordinator.registerRefresh(tab: 3) {
                Task { await loadInboxConversations() }
            }
            if tabCoordinator.openInboxListOnly {
                tabCoordinator.openInboxListOnly = false
                path = []
                guard !authService.isGuestMode else { return }
                inboxViewModel.updateAuthToken(authService.authToken)
                inboxViewModel.refresh()
                return
            }
            if path.isEmpty, let preview = tabCoordinator.lastMessagePreviewForConversation {
                inboxViewModel.updatePreview(conversationId: preview.id, text: preview.text, date: preview.date)
            }
            if let conv = tabCoordinator.pendingOpenConversation {
                tabCoordinator.pendingOpenConversation = nil
                DispatchQueue.main.async { path = [.conversation(conv, isArchived: false)] }
            }
            guard !authService.isGuestMode else { return }
            inboxViewModel.updateAuthToken(authService.authToken)
            if hasNoInboxData && !isLoading {
                inboxViewModel.refresh()
            }
        }
        .onChange(of: path.count) { oldCount, newCount in
            if oldCount > 0, newCount == 0, !authService.isGuestMode {
                if let preview = tabCoordinator.lastMessagePreviewForConversation {
                    inboxViewModel.updatePreview(conversationId: preview.id, text: preview.text, date: preview.date)
                }
                if let conv = tabCoordinator.pendingArchiveWithUndo {
                    tabCoordinator.pendingArchiveWithUndo = nil
                    inboxViewModel.applyArchivedFromDetail(conv)
                    presentArchiveUndo(for: conv)
                }
                Task { await loadInboxConversations() }
            }
        }
        .onChange(of: tabCoordinator.pendingOpenConversation) { _, pending in
            guard let conv = pending else { return }
            tabCoordinator.pendingOpenConversation = nil
            Task {
                await loadInboxConversations()
                await MainActor.run {
                    if !conversations.contains(where: { $0.id == conv.id }) {
                        inboxViewModel.prependConversation(Conversation(
                            id: conv.id,
                            recipient: conv.recipient,
                            lastMessage: conv.lastMessage,
                            lastMessageTime: conv.lastMessageTime ?? Date(),
                            unreadCount: conv.unreadCount,
                            offer: conv.offer,
                            order: conv.order
                        ))
                    }
                    path = [.conversation(conv, isArchived: false)]
                }
            }
        }
        .onChange(of: authService.authToken) { _, newToken in
            inboxViewModel.updateAuthToken(newToken)
        }
        .onChange(of: tabCoordinator.inboxListRefreshNonce) { _, _ in
            guard !authService.isGuestMode else { return }
            Task { await loadInboxConversations() }
        }
    }

    private func archiveConversation(_ conversation: Conversation) {
        guard let convId = Int(conversation.id), convId > 0 else { return }
        Task {
            await inboxViewModel.archiveConversation(conversationId: convId)
            await MainActor.run {
                guard inboxViewModel.errorMessage == nil else { return }
                presentArchiveUndo(for: conversation)
            }
        }
    }

    private func presentArchiveUndo(for conversation: Conversation) {
        archiveUndoDismissTask?.cancel()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            archiveUndoConversation = conversation
        }
        archiveUndoDismissTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                dismissArchiveUndoToast(animated: true)
            }
        }
    }

    private func dismissArchiveUndoToast(animated: Bool) {
        archiveUndoDismissTask?.cancel()
        archiveUndoDismissTask = nil
        if animated {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
                archiveUndoConversation = nil
            }
        } else {
            archiveUndoConversation = nil
        }
    }

    private func undoLastArchiveSwipe() {
        guard let conv = archiveUndoConversation, let cid = Int(conv.id), cid > 0 else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        dismissArchiveUndoToast(animated: true)
        Task { await inboxViewModel.unarchiveConversation(conversationId: cid) }
    }

    private func unarchiveConversation(_ conversation: Conversation) {
        guard let convId = Int(conversation.id), convId > 0 else { return }
        Task { await inboxViewModel.unarchiveConversation(conversationId: convId) }
    }

    /// Load conversations (with optional preview from tabCoordinator) and clear preview after.
    private func loadInboxConversations() async {
        let preview = tabCoordinator.lastMessagePreviewForConversation
        let previewTuple: (id: String, text: String, date: Date)? = preview.map { ($0.id, $0.text, $0.date) }
        await inboxViewModel.loadConversationsAsync(preview: previewTuple, currentUsername: authService.username)
        if preview != nil { tabCoordinator.lastMessagePreviewForConversation = nil }
    }
    
    private var filteredConversations: [Conversation] {
        var list: [Conversation]
        switch inboxFilter {
        case .archived:
            list = archivedConversations
        default:
            list = conversations
        }
        switch inboxFilter {
        case .all, .archived: break
        case .unread: list = list.filter { $0.unreadCount > 0 }
        case .read: list = list.filter { $0.unreadCount == 0 }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return list }
        return list.filter {
            let title = PreluraSupportBranding.displayTitle(forRecipientUsername: $0.recipient.username).lowercased()
            return $0.recipient.username.lowercased().contains(query)
                || title.contains(query)
                || ($0.lastMessage?.lowercased().contains(query) ?? false)
        }
    }

}

private struct ArchiveUndoToast: View {
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(L10n.string("Archived"))
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.primaryText)
            Spacer(minLength: 8)
            Button(L10n.string("Undo")) {
                onUndo()
            }
            .font(Theme.Typography.subheadline.weight(.semibold))
            .foregroundColor(Theme.primaryColor)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .frame(minHeight: Theme.AppBar.buttonSize - 4)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.Colors.secondaryBackground)
                .shadow(color: Color.black.opacity(0.28), radius: 14, y: 5)
        )
    }
}

struct ChatRowView: View {
    let conversation: Conversation
    var currentUsername: String?
    /// From global conversations WebSocket `typing_status` for this thread.
    var isPeerTyping: Bool = false

    private static var offerProductImageCache: [Int: String] = [:]
    private let productService = ProductService()

    @State private var loadedOfferProductImageURL: String?
    @State private var isLoadingOfferProductImage = false

    /// Interpret `1:13` as `width:height = 1:1.3` (so the thumbnail isn't extremely thin).
    private static let productThumbWidthToHeightRatio: CGFloat = 1.0 / 1.3
    private static let productThumbHeight: CGFloat = 44

    private var offerThumbProductId: Int? {
        guard conversation.order == nil else { return nil } // order thumbnails come from `conversation.order`
        return conversation.offer?.products?.first?.id.flatMap { Int($0) }
    }

    private var productImageURL: URL? {
        if let s = conversation.order?.firstProductImageUrl, !s.isEmpty {
            return ProductListImageURL.url(forListDisplay: s)
        }
        if let id = offerThumbProductId {
            if let s = Self.offerProductImageCache[id] ?? loadedOfferProductImageURL, !s.isEmpty {
                return ProductListImageURL.url(forListDisplay: s) ?? URL(string: s)
            }
        }
        return nil
    }

    private func loadOfferProductThumbnailIfNeeded(for productId: Int) async {
        if isLoadingOfferProductImage { return }
        if let cached = Self.offerProductImageCache[productId] {
            await MainActor.run { loadedOfferProductImageURL = cached }
            return
        }
        isLoadingOfferProductImage = true
        defer { isLoadingOfferProductImage = false }

        guard let product = try? await productService.getProduct(id: productId) else { return }
        let thumbURL = product.thumbnailURLForChrome
        await MainActor.run {
            guard let thumbURL, !thumbURL.isEmpty else { return }
            Self.offerProductImageCache[productId] = thumbURL
            loadedOfferProductImageURL = thumbURL
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar (branded for system Prelura Support account)
            if PreluraSupportBranding.isSupportRecipient(username: conversation.recipient.username) {
                PreluraSupportBranding.supportAvatar(size: 50)
            } else if let avatarURL = conversation.recipient.avatarURL, let url = URL(string: avatarURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Circle()
                        .fill(Theme.primaryColor)
                        .overlay(
                            Text(String(conversation.recipient.username.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 50, height: 50)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.primaryColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(conversation.recipient.username.prefix(1)).uppercased())
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
            
            // Content
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(PreluraSupportBranding.displayTitle(forRecipientUsername: conversation.recipient.username))
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.primaryText)

                    Text("• \(displayTimeText)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                
                Group {
                    if isPeerTyping {
                        Text(peerTypingLine)
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.primaryColor)
                            .lineLimit(1)
                    } else {
                        Text(displayPreviewText)
                            .font(Theme.Typography.subheadline)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 0)

            // Product thumbnail (right side).
            ZStack(alignment: .topTrailing) {
                Group {
                    if let url = productImageURL {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            ImageShimmerPlaceholderFilled(cornerRadius: 8)
                        }
                    } else {
                        ImageShimmerPlaceholderFilled(cornerRadius: 8)
                    }
                }
                .frame(
                    width: productThumbWidth,
                    height: Self.productThumbHeight
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Unread badge overlay.
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.primaryColor)
                        .clipShape(Capsule())
                        .offset(x: 4, y: -6)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
        .task(id: offerThumbProductId) {
            // Only fetch thumbnail for offer conversations when we don't already have one.
            guard let productId = offerThumbProductId else { return }
            if conversation.order != nil { return }
            if Self.offerProductImageCache[productId] != nil { return }
            guard loadedOfferProductImageURL == nil, !isLoadingOfferProductImage else { return }
            await loadOfferProductThumbnailIfNeeded(for: productId)
        }
    }

    private var productThumbWidth: CGFloat {
        Self.productThumbHeight * Self.productThumbWidthToHeightRatio
    }

    /// Keep row layout stable: always show a time label.
    private var displayTimeText: String {
        guard let t = conversation.lastMessageTime else { return "—" }
        return formatTime(t)
    }

    /// Keep row layout stable: always show a subtitle line.
    private var displayPreviewText: String {
        ChatRowView.previewText(
            for: conversation.lastMessage,
            conversation: conversation,
            currentUsername: currentUsername
        ) ?? "No messages yet"
    }

    private var peerTypingLine: String {
        let name = PreluraSupportBranding.displayTitle(forRecipientUsername: conversation.recipient.username)
        return "\(name) is typing"
    }
    
    private func formatTime(_ date: Date) -> String {
        let now = Date()
        if now.timeIntervalSince(date) < 60 {
            return L10n.string("Just now")
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let str = formatter.localizedString(for: date, relativeTo: now)
        // iOS formatter returns values like "6 min ago"; UI wants just "6 min".
        if str.lowercased().hasSuffix(" ago") {
            return String(str.dropLast(4))
        }
        return str
    }

    /// Case-insensitive username match so backend "Testuser" matches "testuser".
    fileprivate static func usernamesMatch(_ a: String?, _ b: String?) -> Bool {
        guard let a = a?.trimmingCharacters(in: .whitespaces).lowercased(),
              let b = b?.trimmingCharacters(in: .whitespaces).lowercased(),
              !a.isEmpty, !b.isEmpty else { return false }
        return a == b
    }

    /// Inbox line for order threads: `lastMessage` JSON often uses `type: "order"` (payment / try-cart) while `sold_confirmation` is a separate type — map **CONFIRMED** to "Order confirmed" instead of generic "Order update".
    fileprivate static func orderPreviewLine(for conversation: Conversation) -> String {
        guard let order = conversation.order else { return "Order update" }
        let st = order.status.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if st.contains("HOLD") || st.contains("ISSUE") || st.contains("PAUSE") {
            return "Order on hold"
        }
        switch st {
        case "CONFIRMED": return "Order confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED", "REFUNDED": return "Cancelled"
        default: return "Order update"
        }
    }

    /// Inbox subtitle: show the latest **chat line** (`lastMessage` from API is the latest plain row). Legacy rows may still be JSON — map those to short labels.
    static func previewText(for raw: String?, conversation: Conversation, currentUsername: String?) -> String? {
        let iSentLastOffer = usernamesMatch(conversation.lastMessageSenderUsername, currentUsername)
        guard let raw = raw, !raw.isEmpty else {
            if let offer = conversation.offer {
                let amount = CurrencyFormatter.gbp(offer.offerPrice)
                let buyerName = offer.buyer?.username?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let me = currentUsername?.trimmingCharacters(in: .whitespacesAndNewlines),
                   let buyerName,
                   !buyerName.isEmpty,
                   buyerName.lowercased() == me.lowercased() {
                    return "You offered \(amount)"
                }
                return (buyerName?.isEmpty == false) ? "\(buyerName!) offered \(amount)" : nil
            }
            if conversation.order != nil {
                return orderPreviewLine(for: conversation)
            }
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            if conversation.order != nil {
                return orderPreviewLine(for: conversation)
            }
            return nil
        }
        // Normal case after backend `lastMessage` resolver: plain user text.
        if !trimmed.hasPrefix("{") {
            return trimmed.count > 60 ? String(trimmed.prefix(57)) + "..." : trimmed
        }
        if trimmed.contains("offer_id") || (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any])?["offer_id"] != nil {
            return iSentLastOffer ? "You sent an offer" : "Offer received"
        }
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return raw.count > 60 ? String(raw.prefix(57)) + "..." : raw
        }
        switch type {
        case "order_issue":
            if usernamesMatch(conversation.lastMessageSenderUsername, currentUsername) {
                return "You reported an issue"
            }
            if let sender = conversation.lastMessageSenderUsername?.trimmingCharacters(in: .whitespacesAndNewlines), !sender.isEmpty {
                return "\(sender) reported an issue"
            }
            return "Issue reported"
        case "order": return orderPreviewLine(for: conversation)
        case "offer": return iSentLastOffer ? "You sent an offer" : "Offer received"
        case "account_report": return Message.humanReadableReportLine(json: json, reportType: type, maxLength: 56)
        case "product_report": return Message.humanReadableReportLine(json: json, reportType: type, maxLength: 56)
        case "sold_confirmation":
            if usernamesMatch(conversation.offer?.products?.first?.seller?.username, currentUsername) {
                return "You made a sale 🎉"
            }
            return "Order confirmed"
        case "order_cancellation_request":
            let bySeller = (json["requested_by_seller"] as? Bool) ?? (json["requestedBySeller"] as? Bool) ?? false
            if usernamesMatch(conversation.lastMessageSenderUsername, currentUsername) {
                return "You requested cancellation"
            }
            return bySeller ? "Seller asked to cancel order" : "Buyer asked to cancel order"
        case "order_cancellation_outcome":
            let approved = (json["approved"] as? Bool) ?? false
            return approved ? "Order cancellation was approved" : "Order cancellation was declined"
        default: return raw.count > 60 ? String(raw.prefix(57)) + "..." : raw
        }
    }
}

#Preview {
    ChatListView(tabCoordinator: TabCoordinator(), path: .constant([]), inboxViewModel: InboxViewModel())
        .preferredColorScheme(.dark)
}
