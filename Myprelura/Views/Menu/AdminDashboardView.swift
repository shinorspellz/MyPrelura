import SwiftUI

/// Admin-only submenu: Delete all orders, messages, notifications, offers, delete user. Shown when logged in as Admin.
/// Confirms with count (e.g. "Delete 500 messages?") and shows new count when done.
struct AdminDashboardView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService = ChatService()
    @StateObject private var adminService = AdminService(client: GraphQLClient())
    private let notificationService = NotificationService()

    // Delete user (flag user)
    @State private var showDeleteUserSheet = false
    @State private var deleteUserResult: String? = nil
    @State private var showDeleteUserResult = false
    @State private var isDeletingUser = false

    // Delete all orders
    @State private var ordersConfirmCount: Int? = nil
    @State private var showOrdersConfirm = false
    @State private var ordersResult: String? = nil
    @State private var showOrdersResult = false
    @State private var isDeletingOrders = false

    // Delete all messages (conversations)
    @State private var messagesConfirmCount: Int? = nil
    @State private var showMessagesConfirm = false
    @State private var messagesResult: String? = nil
    @State private var showMessagesResult = false
    @State private var isDeletingMessages = false

    // Delete all notifications
    @State private var notificationsConfirmCount: Int = 0
    @State private var showNotificationsConfirm = false
    @State private var notificationsResult: String? = nil
    @State private var showNotificationsResult = false
    @State private var isDeletingNotifications = false

    // Delete all offers (unsupported)
    @State private var showOffersUnsupported = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    AdminAllOrdersView()
                } label: {
                    adminRow("Orders", icon: "bag", isDestructive: false)
                }
                NavigationLink {
                    AdminOrderIssuesView()
                } label: {
                    adminRow("Order issues", icon: "exclamationmark.bubble", isDestructive: false)
                }
                NavigationLink {
                    AdminReportsView()
                } label: {
                    adminRow("Reports", icon: "flag", isDestructive: false)
                }
            }
            Section {
                Button(role: .destructive, action: { showDeleteUserSheet = true }) {
                    adminRow("Delete user", icon: "person.crop.circle.badge.minus")
                }
                .disabled(isDeletingUser)

                Button(role: .destructive, action: { prepareDeleteAllOrders() }) {
                    adminRow("Delete all orders", icon: "bag.badge.minus")
                }
                .disabled(isDeletingOrders)

                Button(role: .destructive, action: { prepareDeleteAllMessages() }) {
                    adminRow("Delete all messages", icon: "message.badge")
                }
                .disabled(isDeletingMessages)

                Button(role: .destructive, action: { prepareDeleteAllNotifications() }) {
                    adminRow("Delete all notifications", icon: "bell.badge")
                }
                .disabled(isDeletingNotifications)

                Button(action: { showOffersUnsupported = true }) {
                    adminRow("Delete all offers", icon: "tag.slash", isDestructive: false)
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Admin Dashboard"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if let token = authService.authToken {
                chatService.updateAuthToken(token)
                adminService.updateAuthToken(token)
                notificationService.updateAuthToken(token)
            }
        }
        .sheet(isPresented: $showDeleteUserSheet) {
            DeleteUserSheet(
                adminService: adminService,
                isDeleting: $isDeletingUser,
                onDone: { message in
                    showDeleteUserSheet = false
                    deleteUserResult = message
                    showDeleteUserResult = true
                },
                onCancel: { showDeleteUserSheet = false }
            )
        }
        .alert("Result", isPresented: $showDeleteUserResult) {
            Button("OK") { deleteUserResult = nil }
        } message: {
            Text(deleteUserResult ?? "")
        }
        .alert("Delete all orders?", isPresented: $showOrdersConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { ordersConfirmCount = nil }
            Button("Delete", role: .destructive) { performDeleteAllOrders() }
        } message: {
            if let n = ordersConfirmCount {
                Text("This will delete all orders and payments in the database, plus \(n) conversations. This cannot be undone.")
            }
        }
        .alert("Result", isPresented: $showOrdersResult) {
            Button("OK") { ordersResult = nil }
        } message: {
            Text(ordersResult ?? "")
        }
        .alert("Delete all messages?", isPresented: $showMessagesConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { messagesConfirmCount = nil }
            Button("Delete", role: .destructive) { performDeleteAllMessages() }
        } message: {
            if let n = messagesConfirmCount {
                Text("This will delete \(n) conversations and all their messages. This cannot be undone.")
            }
        }
        .alert("Result", isPresented: $showMessagesResult) {
            Button("OK") { messagesResult = nil }
        } message: {
            Text(messagesResult ?? "")
        }
        .alert("Delete all notifications?", isPresented: $showNotificationsConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { }
            Button("Delete", role: .destructive) { performDeleteAllNotifications() }
        } message: {
            Text("This will delete \(notificationsConfirmCount) notifications. This cannot be undone.")
        }
        .alert("Result", isPresented: $showNotificationsResult) {
            Button("OK") { notificationsResult = nil }
        } message: {
            Text(notificationsResult ?? "")
        }
        .alert("Delete all offers", isPresented: $showOffersUnsupported) {
            Button("OK") { }
        } message: {
            Text("Not supported by the backend yet.")
        }
    }

    private func adminRow(_ title: String, icon: String, isDestructive: Bool = true) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(isDestructive ? .red : Theme.Colors.secondaryText)
            Text(title)
                .foregroundColor(isDestructive ? .red : Theme.Colors.primaryText)
        }
    }

    private func prepareDeleteAllOrders() {
        Task {
            do {
                let convs = try await chatService.getConversations()
                await MainActor.run {
                    ordersConfirmCount = convs.count
                    showOrdersConfirm = true
                }
            } catch {
                await MainActor.run {
                    ordersResult = "Could not load count: \(error.localizedDescription)"
                    showOrdersResult = true
                }
            }
        }
    }

    private func performDeleteAllOrders() {
        isDeletingOrders = true
        Task {
            do {
                let (success, message, _, _) = try await chatService.deleteAllConversations()
                await MainActor.run {
                    isDeletingOrders = false
                    ordersConfirmCount = nil
                    if success {
                        ordersResult = "Done. Orders: 0, Conversations: 0."
                        NotificationCenter.default.post(name: .preluraSellerEarningsShouldRefresh, object: nil)
                    } else {
                        ordersResult = message ?? "Delete failed."
                    }
                    showOrdersResult = true
                }
            } catch {
                await MainActor.run {
                    isDeletingOrders = false
                    ordersConfirmCount = nil
                    ordersResult = error.localizedDescription
                    showOrdersResult = true
                }
            }
        }
    }

    private func prepareDeleteAllMessages() {
        Task {
            do {
                let convs = try await chatService.getConversations()
                await MainActor.run {
                    messagesConfirmCount = convs.count
                    showMessagesConfirm = true
                }
            } catch {
                await MainActor.run {
                    messagesResult = "Could not load count: \(error.localizedDescription)"
                    showMessagesResult = true
                }
            }
        }
    }

    private func performDeleteAllMessages() {
        isDeletingMessages = true
        Task {
            do {
                let (success, message, _, _) = try await chatService.deleteAllConversations()
                await MainActor.run {
                    isDeletingMessages = false
                    messagesConfirmCount = nil
                    if success {
                        messagesResult = "Done. Messages: 0, Conversations: 0."
                    } else {
                        messagesResult = message ?? "Delete failed."
                    }
                    showMessagesResult = true
                }
            } catch {
                await MainActor.run {
                    isDeletingMessages = false
                    messagesConfirmCount = nil
                    messagesResult = error.localizedDescription
                    showMessagesResult = true
                }
            }
        }
    }

    private func prepareDeleteAllNotifications() {
        Task {
            do {
                let (_, total) = try await notificationService.getNotifications(pageCount: 1, pageNumber: 1)
                await MainActor.run {
                    notificationsConfirmCount = total
                    showNotificationsConfirm = true
                }
            } catch {
                await MainActor.run {
                    notificationsResult = "Could not load count: \(error.localizedDescription)"
                    showNotificationsResult = true
                }
            }
        }
    }

    private func performDeleteAllNotifications() {
        isDeletingNotifications = true
        Task {
            do {
                var allIds: [Int] = []
                var page = 1
                let pageSize = 50
                while true {
                    let (notifications, total) = try await notificationService.getNotifications(pageCount: pageSize, pageNumber: page)
                    for n in notifications {
                        if let id = Int(n.id) {
                            allIds.append(id)
                        }
                    }
                    if allIds.count >= total || notifications.count < pageSize {
                        break
                    }
                    page += 1
                }
                for id in allIds {
                    _ = try await notificationService.deleteNotification(notificationId: id)
                }
                await MainActor.run {
                    isDeletingNotifications = false
                    notificationsResult = "Done. Notifications: 0."
                    showNotificationsResult = true
                }
            } catch {
                await MainActor.run {
                    isDeletingNotifications = false
                    notificationsResult = error.localizedDescription
                    showNotificationsResult = true
                }
            }
        }
    }
}

// MARK: - Delete user sheet (admin: username + reason → flagUser)
private enum FlagUserReason: String, CaseIterable {
    case termsViolation = "TERMS_VIOLATION"
    case spamActivity = "SPAM_ACTIVITY"
    case inappropriateContent = "INAPPROPRIATE_CONTENT"
    case harassment = "HARASSMENT"
    case legalRequest = "LEGAL_REQUEST"
    case other = "OTHER"

    var displayName: String {
        switch self {
        case .termsViolation: return "Terms violation"
        case .spamActivity: return "Spam"
        case .inappropriateContent: return "Inappropriate content"
        case .harassment: return "Harassment"
        case .legalRequest: return "Legal / admin decision"
        case .other: return "Other"
        }
    }
}

private struct DeleteUserSheet: View {
    @ObservedObject var adminService: AdminService
    @Binding var isDeleting: Bool
    var onDone: (String) -> Void
    var onCancel: () -> Void

    @State private var username: String = ""
    @State private var selectedReason: FlagUserReason = .other
    @State private var notes: String = ""
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("User to delete")
                } footer: {
                    Text("Enter the exact username. The account will be flagged and soft-deleted.")
                }

                Section("Reason") {
                    Picker("Reason", selection: $selectedReason) {
                        ForEach(FlagUserReason.allCases, id: \.self) { r in
                            Text(r.displayName).tag(r)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Notes (optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(Theme.Colors.error)
                            .font(Theme.Typography.caption)
                    }
                }
            }
            .navigationTitle("Delete user")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Delete", role: .destructive) {
                        performDelete()
                    }
                    .disabled(username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isDeleting)
                }
            }
        }
    }

    private func performDelete() {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        errorMessage = nil
        isDeleting = true
        Task {
            do {
                let users = try await adminService.fetchUserAdminStats(search: name, pageCount: 10, pageNumber: 1)
                let exact = users.first { $0.username?.lowercased() == name.lowercased() }
                let target = exact ?? users.first
                guard let user = target, let idStr = user.idString else {
                    await MainActor.run {
                        isDeleting = false
                        errorMessage = users.isEmpty ? "No user found with that username." : "No exact match. Please enter the full username."
                    }
                    return
                }
                let (success, message) = try await adminService.flagUser(id: idStr, reason: selectedReason.rawValue, notes: notes.isEmpty ? nil : notes)
                await MainActor.run {
                    isDeleting = false
                    dismiss()
                    onDone(success ? (message ?? "User deleted.") : (message ?? "Delete failed."))
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
