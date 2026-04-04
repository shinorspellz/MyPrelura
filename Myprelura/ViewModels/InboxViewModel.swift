import Foundation
import SwiftUI
import Combine

@MainActor
class InboxViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    /// Threads archived by the current user (from `archivedConversations` query).
    @Published var archivedConversations: [Conversation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// Conversation ids where the peer is typing (from `ws/conversations/` typing_status).
    @Published private(set) var peerTypingConversationIds: Set<String> = []

    private let chatService = ChatService()
    private var authToken: String?
    private var conversationsSocket: ConversationsWebSocketService?
    private var socketRefreshTask: Task<Void, Never>?
    private var typingAutoHideTasks: [String: Task<Void, Never>] = [:]

    init() {}

    func updateAuthToken(_ token: String?) {
        authToken = token
        chatService.updateAuthToken(token)
        reconnectConversationsSocket()
    }

    /// Global `ws/conversations/` — refreshes inbox when server pushes `update_conversation` (new messages, offers, etc.).
    private func reconnectConversationsSocket() {
        conversationsSocket?.disconnect()
        conversationsSocket = nil
        socketRefreshTask?.cancel()
        socketRefreshTask = nil
        guard let token = authToken, !token.isEmpty else { return }
        let socket = ConversationsWebSocketService(token: token)
        socket.onShouldRefreshConversationsList = { [weak self] in
            self?.scheduleDebouncedConversationsRefresh()
        }
        socket.onTypingStatus = { [weak self] conversationId, isTyping in
            self?.applyPeerTypingListIndicator(conversationId: conversationId, isTyping: isTyping)
        }
        socket.connect()
        conversationsSocket = socket
    }

    /// Apply typing indicator for inbox rows (server only notifies the other participant).
    func applyPeerTypingListIndicator(conversationId: String, isTyping: Bool) {
        typingAutoHideTasks[conversationId]?.cancel()
        typingAutoHideTasks[conversationId] = nil
        var next = peerTypingConversationIds
        if isTyping {
            next.insert(conversationId)
            peerTypingConversationIds = next
            typingAutoHideTasks[conversationId] = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self else { return }
                self.typingAutoHideTasks[conversationId] = nil
                var n = self.peerTypingConversationIds
                n.remove(conversationId)
                self.peerTypingConversationIds = n
            }
        } else {
            next.remove(conversationId)
            peerTypingConversationIds = next
        }
    }

    /// Coalesce bursts (e.g. several `update_conversation` in one second) into one GraphQL fetch.
    private func scheduleDebouncedConversationsRefresh() {
        socketRefreshTask?.cancel()
        socketRefreshTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await loadConversationsAsync(preview: nil)
        }
    }

    /// Prefetch conversations in the background (e.g. from MainTabView.onAppear). Safe to call when already loading.
    func prefetch() {
        guard !isLoading, conversations.isEmpty, archivedConversations.isEmpty else { return }
        Task { await loadConversationsAsync(preview: nil) }
    }

    /// Full refresh. Call from Inbox when user pulls to refresh or first appears with no data.
    func refresh() {
        Task { await loadConversationsAsync(preview: nil) }
    }

    /// Load conversations from API. Merges in existing conversations not in API response; applies optional preview for one conversation.
    func loadConversationsAsync(preview: (id: String, text: String, date: Date)?) async {
        let hadConversations = !conversations.isEmpty || !archivedConversations.isEmpty
        let existingToMerge = conversations
        if !hadConversations {
            isLoading = true
            conversations = []
            archivedConversations = []
        }
        do {
            async let mainTask = chatService.getConversations()
            async let archivedTask = chatService.getArchivedConversations()
            let (fetched, archivedFetched) = try await (mainTask, archivedTask)
            var list = fetched
            let apiIds = Set(list.map(\.id))
            for existing in existingToMerge where !apiIds.contains(existing.id) {
                list.append(existing)
            }
            // Counter-offers must not create duplicate chats: backend may return two conversations for same recipient+product; keep one per (recipient, product set) with latest activity.
            list = Self.deduplicateConversations(list)
            if let preview = preview, let idx = list.firstIndex(where: { $0.id == preview.id }) {
                let c = list[idx]
                let apiTime = c.lastMessageTime ?? .distantPast
                // Prefer the newer of API vs local (leaving chat) so the row updates immediately and isn’t stuck on an older offer row.
                if preview.date >= apiTime {
                    list[idx] = Conversation(
                        id: c.id,
                        recipient: c.recipient,
                        lastMessage: preview.text,
                        lastMessageSenderUsername: c.lastMessageSenderUsername,
                        lastMessageTime: preview.date,
                        unreadCount: c.unreadCount,
                        offer: c.offer,
                        order: c.order,
                        offerHistory: c.offerHistory
                    )
                }
            }
            Self.sortConversationsInPlace(&list)
            conversations = list
            var archivedList = Self.deduplicateConversations(archivedFetched)
            Self.sortConversationsInPlace(&archivedList)
            archivedConversations = archivedList
            errorMessage = nil
            isLoading = false
        } catch {
            let isCancelled = (error as? URLError)?.code == .cancelled
                || error.localizedDescription.lowercased().contains("cancelled")
            isLoading = false
            if isCancelled {
                if hadConversations { errorMessage = nil }
                else { errorMessage = nil; conversations = []; archivedConversations = [] }
            } else {
                errorMessage = error.localizedDescription
                if hadConversations { } else { conversations = []; archivedConversations = [] }
            }
        }
    }

    /// Update one conversation's last message preview (e.g. after sending).
    func updatePreview(conversationId: String, text: String, date: Date) {
        guard let idx = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        let c = conversations[idx]
        conversations[idx] = Conversation(
            id: c.id,
            recipient: c.recipient,
            lastMessage: text,
            lastMessageSenderUsername: c.lastMessageSenderUsername,
            lastMessageTime: date,
            unreadCount: c.unreadCount,
            offer: c.offer,
            order: c.order,
            offerHistory: c.offerHistory
        )
        Self.sortConversationsInPlace(&conversations)
    }

    /// Insert a conversation at the top (e.g. newly created before API returns it).
    func prependConversation(_ conv: Conversation) {
        var list = conversations
        if list.contains(where: { $0.id == conv.id }) { return }
        list.insert(conv, at: 0)
        Self.sortConversationsInPlace(&list)
        conversations = list
    }

    /// Remove a conversation from the list (e.g. after delete).
    func removeConversation(id: String) {
        conversations.removeAll { $0.id == id }
    }

    /// Delete conversation on backend and remove from list.
    func deleteConversation(conversationId: Int) async {
        do {
            try await chatService.deleteConversation(conversationId: conversationId)
            removeConversation(id: String(conversationId))
            archivedConversations.removeAll { $0.id == String(conversationId) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// After archive succeeded from chat detail (API already called). Updates lists like `archiveConversation` without a second request.
    func applyArchivedFromDetail(_ conv: Conversation) {
        let idStr = conv.id
        conversations.removeAll { $0.id == idStr }
        var arch = archivedConversations
        if !arch.contains(where: { $0.id == idStr }) {
            arch.append(conv)
        }
        archivedConversations = Self.deduplicateConversations(arch)
        Self.sortConversationsInPlace(&archivedConversations)
        errorMessage = nil
    }

    /// Archive on server; remove from main inbox and show under Archive filter.
    func archiveConversation(conversationId: Int) async {
        let idStr = String(conversationId)
        do {
            try await chatService.archiveConversation(conversationId: conversationId)
            guard let conv = conversations.first(where: { $0.id == idStr }) else {
                await loadConversationsAsync(preview: nil)
                return
            }
            conversations.removeAll { $0.id == idStr }
            var arch = archivedConversations
            if !arch.contains(where: { $0.id == idStr }) {
                arch.append(conv)
            }
            archivedConversations = Self.deduplicateConversations(arch)
            Self.sortConversationsInPlace(&archivedConversations)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Unarchive on server; return thread to main inbox list.
    func unarchiveConversation(conversationId: Int) async {
        let idStr = String(conversationId)
        do {
            try await chatService.unarchiveConversation(conversationId: conversationId)
            guard let conv = archivedConversations.first(where: { $0.id == idStr }) else {
                await loadConversationsAsync(preview: nil)
                return
            }
            archivedConversations.removeAll { $0.id == idStr }
            var list = conversations
            if !list.contains(where: { $0.id == idStr }) {
                list.append(conv)
            }
            conversations = Self.deduplicateConversations(list)
            Self.sortConversationsInPlace(&conversations)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Deduplicate so counter-offers don't show as a second chat. For offer conversations: same recipient + same offer product set = one conversation (keep latest by lastMessageTime). Non-offer conversations are left as-is.
    private static func deduplicateConversations(_ list: [Conversation]) -> [Conversation] {
        func key(_ c: Conversation) -> String {
            // Order threads stay one row per conversation (repeat purchases from same seller = separate chats).
            if c.order != nil {
                return "conv|\(c.id)"
            }
            if let productIds = c.offer?.products?.compactMap(\.id), !productIds.isEmpty {
                return "offer|\(c.recipient.username)|\(productIds.sorted().joined(separator: ","))"
            }
            return "conv|\(c.id)"
        }
        var byKey: [String: Conversation] = [:]
        for c in list {
            let k = key(c)
            let existing = byKey[k]
            let cTime = c.lastMessageTime ?? .distantPast
            let existingTime = existing?.lastMessageTime ?? .distantPast
            if existing == nil {
                byKey[k] = c
            } else if cTime > existingTime {
                byKey[k] = c
            } else if cTime == existingTime, let ex = existing {
                // Same activity time: pick deterministically so list order doesn’t flip when API order changes.
                if c.id < ex.id { byKey[k] = c }
            }
        }
        return Array(byKey.values)
    }

    /// Newest first; tie-break by `id` so rows with identical `lastMessageTime` (e.g. same minute) don’t reorder between refreshes.
    private static func sortConversationsInPlace(_ list: inout [Conversation]) {
        list.sort { a, b in
            let ta = a.lastMessageTime ?? .distantPast
            let tb = b.lastMessageTime ?? .distantPast
            if ta != tb { return ta > tb }
            return a.id < b.id
        }
    }
}
