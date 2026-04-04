import SwiftUI

/// List of in-app notifications (Flutter NotificationsScreen + NotificationsTab).
struct NotificationsListView: View {
    @EnvironmentObject private var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    @State private var notifications: [AppNotification] = []
    @State private var totalNumber: Int = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var errorMessage: String?
    @State private var page = 1
    private let pageSize = 15
    private let notificationService = NotificationService()

    var body: some View {
        Group {
            if isLoading && notifications.isEmpty && errorMessage == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage, notifications.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(err)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        errorMessage = nil
                        Task { await load(page: 1) }
                    }
                    .foregroundColor(Theme.primaryColor)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if notifications.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48))
                        .foregroundColor(Theme.Colors.secondaryText)
                    Text(L10n.string("No notifications"))
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(notifications) { notification in
                        NavigationLink(destination: NotificationDestinationView(notification: notification, onMarkRead: { markAsRead(notification) })) {
                            NotificationRowView(notification: notification)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        .listRowBackground(Theme.Colors.background)
                        .listRowInsets(EdgeInsets(top: 4, leading: Theme.Spacing.md, bottom: 4, trailing: Theme.Spacing.md))
                        .navigationLinkIndicatorVisibility(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteNotification(notification)
                            } label: {
                                Label(L10n.string("Delete"), systemImage: "trash")
                            }
                        }
                    }
                    .listRowBackground(Theme.Colors.background)
                    if notifications.count < totalNumber {
                        HStack {
                            Spacer()
                            if isLoadingMore { ProgressView() }
                            Spacer()
                        }
                        .onAppear { Task { await loadMore() } }
                        .listRowBackground(Theme.Colors.background)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Notifications"))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await load(page: 1)
        }
        .onAppear {
            notificationService.updateAuthToken(authService.authToken)
            Task { await load(page: 1) }
        }
        .onChange(of: authService.authToken) { _, newToken in
            notificationService.updateAuthToken(newToken)
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private func load(page: Int) async {
        if page == 1 {
            isLoading = true
            errorMessage = nil
            notifications = []
        } else {
            isLoadingMore = true
        }
        defer {
            if page == 1 { isLoading = false } else { isLoadingMore = false }
        }
        do {
            notificationService.updateAuthToken(authService.authToken)
            let (list, total) = try await notificationService.getNotifications(pageCount: pageSize, pageNumber: page)
            await MainActor.run {
                if page == 1 {
                    notifications = list
                    totalNumber = total
                    self.page = 1
                } else {
                    notifications.append(contentsOf: list)
                    self.page = page
                }
            }
        } catch {
            await MainActor.run { errorMessage = L10n.userFacingError(error) }
        }
    }

    private func loadMore() async {
        guard !isLoading, !isLoadingMore, notifications.count < totalNumber else { return }
        await load(page: page + 1)
    }
    
    private func markAsRead(_ notification: AppNotification) {
        guard let idInt = Int(notification.id) else { return }
        Task {
            _ = try? await notificationService.readNotifications(notificationIds: [idInt])
            await MainActor.run {
                if let idx = notifications.firstIndex(where: { $0.id == notification.id }) {
                    notifications[idx] = AppNotification(
                        id: notifications[idx].id,
                        sender: notifications[idx].sender,
                        message: notifications[idx].message,
                        model: notifications[idx].model,
                        modelId: notifications[idx].modelId,
                        modelGroup: notifications[idx].modelGroup,
                        isRead: true,
                        createdAt: notifications[idx].createdAt,
                        meta: notifications[idx].meta
                    )
                }
            }
        }
    }
    
    private func deleteNotification(_ notification: AppNotification) {
        guard let idInt = Int(notification.id) else { return }
        Task {
            do {
                _ = try await notificationService.deleteNotification(notificationId: idInt)
                await MainActor.run {
                    notifications.removeAll { $0.id == notification.id }
                    totalNumber = max(0, totalNumber - 1)
                }
            } catch {
                await MainActor.run { errorMessage = L10n.userFacingError(error) }
            }
        }
    }
}

// MARK: - Notification tap destination (product, profile, or chat)

/// Resolves and presents the appropriate screen when user taps a notification (matches Flutter NotificationCard navigation).
struct NotificationDestinationView: View {
    let notification: AppNotification
    var onMarkRead: (() -> Void)? = nil
    @EnvironmentObject private var authService: AuthService

    @State private var resolvedItem: Item?
    @State private var resolvedUser: User?
    @State private var resolvedConversation: Conversation?
    @State private var isLoading = true
    @State private var loadError: String?

    private let productService = ProductService()
    private let userService = UserService()
    private let chatService = ChatService()

    var body: some View {
        content
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            productService.updateAuthToken(authService.authToken)
            userService.updateAuthToken(authService.authToken)
            chatService.updateAuthToken(authService.authToken)
            onMarkRead?()
            Task { await resolve() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: Theme.Spacing.md) {
                ProgressView()
                if let err = loadError {
                    Text(err)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
        } else if modelGroup == "Product", let item = resolvedItem {
            ItemDetailView(item: item, authService: authService)
        } else if modelGroup == "UserProfile", let user = resolvedUser {
            UserProfileView(seller: user, authService: authService)
        } else if (modelGroup == "Chat" || modelGroup == "Offer" || modelGroup == "Order"), let conv = resolvedConversation {
            ChatDetailView(conversation: conv)
        } else if let err = loadError {
            VStack(spacing: Theme.Spacing.md) {
                Text(err)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
        } else {
            EmptyView()
        }
    }

    private var modelGroup: String {
        (notification.modelGroup ?? "").trimmingCharacters(in: .whitespaces)
    }

    private func resolve() async {
        switch modelGroup {
        case "Product":
            guard let modelId = notification.modelId, let productId = Int(modelId) else {
                await MainActor.run { loadError = "Invalid product"; isLoading = false }
                return
            }
            do {
                let item = try await productService.getProduct(id: productId)
                await MainActor.run {
                    resolvedItem = item
                    loadError = item == nil ? "Product not found" : nil
                    isLoading = false
                }
            } catch {
                await MainActor.run { loadError = L10n.userFacingError(error); isLoading = false }
            }
        case "UserProfile":
            guard let username = notification.sender?.username, !username.isEmpty else {
                await MainActor.run { loadError = "Unknown user"; isLoading = false }
                return
            }
            do {
                let user = try await userService.getUser(username: username)
                await MainActor.run {
                    resolvedUser = user
                    isLoading = false
                }
            } catch {
                await MainActor.run { loadError = L10n.userFacingError(error); isLoading = false }
            }
        case "Chat", "Offer", "Order":
            let convId = notification.meta?["conversation_id"] ?? ""
            let username = notification.sender?.username ?? ""
            let avatarUrl = notification.sender?.profilePictureUrl
            do {
                let convs = try await chatService.getConversations()
                let existing = convs.first { $0.id == convId }
                if let conv = existing {
                    await MainActor.run {
                        resolvedConversation = conv
                        isLoading = false
                    }
                } else {
                    let recipient = User(
                        username: username,
                        displayName: username,
                        avatarURL: avatarUrl
                    )
                    await MainActor.run {
                        resolvedConversation = Conversation(
                            id: convId.isEmpty ? "0" : convId,
                            recipient: recipient,
                            lastMessage: nil,
                            lastMessageTime: nil,
                            unreadCount: 0
                        )
                        isLoading = false
                    }
                }
            } catch {
                let recipient = User(
                    username: username,
                    displayName: username,
                    avatarURL: avatarUrl
                )
                await MainActor.run {
                    resolvedConversation = Conversation(
                        id: convId.isEmpty ? "0" : convId,
                        recipient: recipient,
                        lastMessage: nil,
                        lastMessageTime: nil,
                        unreadCount: 0
                    )
                    isLoading = false
                }
            }
        default:
            await MainActor.run { loadError = "Unknown notification type"; isLoading = false }
        }
    }
}

private struct NotificationRowView: View {
    let notification: AppNotification

    private var senderUsername: String? {
        notification.sender?.username
    }

    private var isSupportNotification: Bool {
        PreluraSupportBranding.isSupportSender(username: senderUsername)
    }

    /// Strips the sender's username from the start of the message (e.g. "shinor Transaction paused" → "Transaction paused").
    private var displayMessage: String {
        let msg = notification.message
        guard let username = notification.sender?.username, !username.isEmpty else { return msg }
        let prefix = username + " "
        if msg.hasPrefix(prefix) {
            return String(msg.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return msg
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if isSupportNotification {
                PreluraSupportBranding.supportAvatar(size: 44)
            } else if let sender = notification.sender, let urlString = sender.profilePictureUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    default:
                        Circle()
                            .fill(Theme.primaryColor.opacity(0.3))
                            .overlay(
                                Text(String((sender.username ?? "?").prefix(1)).uppercased())
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person")
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(displayMessage)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let date = notification.createdAt {
                    Text(formatDate(date))
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

#Preview {
    NavigationStack {
        NotificationsListView()
            .environmentObject(AuthService())
    }
}
