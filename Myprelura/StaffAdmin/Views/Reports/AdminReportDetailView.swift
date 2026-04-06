import SwiftUI

private let kOrderIssueType = "ORDER_ISSUE"
private let kProfanityType = "PROFANITY"

/// Staff report detail: consumer-style chats plus moderation actions by report type.
struct AdminReportDetailView: View {
    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService
    let report: StaffAdminReportRow

    @State private var reportedAccountUserId: Int?
    @State private var actionBusy = false
    @State private var feedbackTitle: String?
    @State private var feedbackMessage: String?
    @State private var showHideListingConfirm = false
    @State private var showDeleteListingConfirm = false
    @State private var showSuspendConfirm = false
    @State private var showBanConfirm = false

    private var reportTitle: String {
        if let p = report.publicId, !p.isEmpty { return p }
        let t = report.reportType ?? "Report"
        return "\(t) #\(report.backendRowId)"
    }

    /// User context for staff support threads: reporter for account reports; offending user for profanity strikes.
    private var supportThreadCustomerUsername: String? {
        if report.reportType == kProfanityType {
            return report.accountReportedUsername
        }
        return report.reportedByUsername ?? report.accountReportedUsername
    }

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Type", value: report.reportType ?? "—")
                LabeledContent("Status", value: report.status ?? "—")
                if let pid = report.publicId, !pid.isEmpty {
                    LabeledContent("Public id", value: pid)
                }
                if report.reportType == kOrderIssueType, let oid = report.orderId {
                    LabeledContent("Order id", value: "\(oid)")
                }
            }

            Section("Details") {
                Text(report.reason ?? "No reason")
                if let ctx = report.context, !ctx.isEmpty {
                    Text(ctx)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }

            if let imgs = report.imagesUrl, !imgs.isEmpty {
                Section("Attachments") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(imgs.enumerated()), id: \.offset) { _, urlStr in
                                if let u = URL(string: urlStr) {
                                    AsyncImage(url: u) { phase in
                                        switch phase {
                                        case .empty:
                                            ProgressView()
                                        case let .success(img):
                                            img.resizable().scaledToFill()
                                        default:
                                            Image(systemName: "photo")
                                        }
                                    }
                                    .frame(width: 120, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            }

            Section("People") {
                if let by = report.reportedByUsername {
                    LabeledContent("Reporter", value: "@\(by)")
                }
                if let acc = report.accountReportedUsername {
                    if let url = Constants.publicProfileURL(username: acc) {
                        NavigationLink {
                            ConsumerWebPageView(url: url, title: "@\(acc)")
                        } label: {
                            Text("Open reported account (web)")
                        }
                    }
                }
            }

            if report.reportType == "PRODUCT", let pid = report.productId {
                Section("Listing") {
                    LabeledContent("Product id", value: "\(pid)")
                    if let name = report.productName {
                        Text(name)
                    }
                    if let url = Constants.publicProductURL(productId: pid, listingCode: nil) {
                        NavigationLink {
                            ConsumerWebPageView(url: url, title: "Listing")
                        } label: {
                            Text("Open listing on wearhouse.co.uk")
                        }
                    }
                }
            }

            linkedChatsSection

            actionsSection
        }
        .navigationTitle(reportTitle)
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .overlay {
            if actionBusy {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView()
                        .padding(24)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .task(id: report.id) { await loadReportedAccountIdIfNeeded() }
        .alert(feedbackTitle ?? "", isPresented: Binding(
            get: { feedbackMessage != nil },
            set: { if !$0 { feedbackMessage = nil; feedbackTitle = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            if let feedbackMessage { Text(feedbackMessage) }
        }
        .alert("Hide this listing?", isPresented: $showHideListingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Hide") { Task { await hideListing() } }
        } message: {
            Text("The listing will be hidden from the marketplace (same as staff flag).")
        }
        .alert("Delete this listing permanently?", isPresented: $showDeleteListingConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await deleteListing() } }
        } message: {
            Text("This cannot be undone.")
        }
        .alert("Suspend this account?", isPresented: $showSuspendConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Suspend", role: .destructive) { Task { await suspendAccount() } }
        } message: {
            Text("Suspends the reported user account.")
        }
        .alert("Ban this account?", isPresented: $showBanConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Ban", role: .destructive) { Task { await banAccount() } }
        } message: {
            Text("Bans the reported user account.")
        }
    }

    @ViewBuilder
    private var linkedChatsSection: some View {
        Section {
            if report.reportType == kOrderIssueType {
                if let cid = report.conversationId {
                    NavigationLink {
                        StaffReportConversationLoaderView(conversationId: String(cid))
                            .environmentObject(authService)
                    } label: {
                        Label("Order chat", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let sid = report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(sid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Buyer support", systemImage: "lifepreserver")
                    }
                }
                if let ssid = report.sellerSupportConversationId, ssid != report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(ssid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Seller support", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
                if report.conversationId == nil, report.supportConversationId == nil, report.sellerSupportConversationId == nil {
                    Text("No linked chat threads.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            } else {
                if let cid = report.conversationId {
                    NavigationLink {
                        StaffReportConversationLoaderView(conversationId: String(cid))
                            .environmentObject(authService)
                    } label: {
                        Label("Open chat", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let sid = report.supportConversationId, sid != report.conversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(sid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Support & help chat", systemImage: "lifepreserver")
                    }
                }
                if report.conversationId == nil, report.supportConversationId == nil {
                    Text("No linked conversation on this report.")
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        } header: {
            Text("Conversation")
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        Section {
            if report.reportType == "PRODUCT", let pid = report.productId {
                Button {
                    showHideListingConfirm = true
                } label: {
                    Label("Hide listing", systemImage: "eye.slash")
                }
                .disabled(actionBusy)

                Button(role: .destructive) {
                    showDeleteListingConfirm = true
                } label: {
                    Label("Delete listing", systemImage: "trash")
                }
                .disabled(actionBusy)

                if let sid = report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(sid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Respond to reporter", systemImage: "arrowshape.turn.up.left.fill")
                    }
                }
            } else if report.reportType == "ACCOUNT" || report.reportType == kProfanityType {
                Button {
                    showSuspendConfirm = true
                } label: {
                    Label("Suspend account", systemImage: "pause.circle")
                }
                .disabled(actionBusy || reportedAccountUserId == nil)

                Button(role: .destructive) {
                    showBanConfirm = true
                } label: {
                    Label("Ban account", systemImage: "hand.raised.fill")
                }
                .disabled(actionBusy || reportedAccountUserId == nil)

                Button {
                    Task { await unsuspendAccount() }
                } label: {
                    Label("Clear suspension", systemImage: "play.circle")
                }
                .disabled(actionBusy || reportedAccountUserId == nil)

                Button {
                    Task { await unbanAccount() }
                } label: {
                    Label("Remove ban", systemImage: "person.crop.circle.badge.checkmark")
                }
                .disabled(actionBusy || reportedAccountUserId == nil)

                if report.reportType == "ACCOUNT", let sid = report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(sid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Open support chat", systemImage: "lifepreserver")
                    }
                }
            } else if report.reportType == kOrderIssueType {
                if let cid = report.conversationId {
                    NavigationLink {
                        StaffReportConversationLoaderView(conversationId: String(cid))
                            .environmentObject(authService)
                    } label: {
                        Label("View order conversation", systemImage: "bubble.left.and.bubble.right")
                    }
                }
                if let sid = report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(sid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Buyer support chat", systemImage: "lifepreserver")
                    }
                }
                if let ssid = report.sellerSupportConversationId, ssid != report.supportConversationId {
                    NavigationLink {
                        HelpChatView(
                            conversationId: String(ssid),
                            isAdminSupportThread: true,
                            customerUsername: supportThreadCustomerUsername
                        )
                        .environmentObject(authService)
                    } label: {
                        Label("Seller support chat", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
            }
        } header: {
            Text("Actions")
        } footer: {
            if (report.reportType == "ACCOUNT" || report.reportType == kProfanityType),
               reportedAccountUserId == nil,
               report.accountReportedUsername != nil {
                Text("Could not resolve user id for moderation actions. Check network or permissions.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    private func loadReportedAccountIdIfNeeded() async {
        let needsUserId = report.reportType == "ACCOUNT" || report.reportType == kProfanityType
        guard needsUserId, let username = report.accountReportedUsername, !username.isEmpty else {
            reportedAccountUserId = nil
            return
        }
        do {
            let profile = try await PreluraAdminAPI.getUser(client: session.graphQL, username: username)
            await MainActor.run { reportedAccountUserId = profile?.id }
        } catch {
            await MainActor.run { reportedAccountUserId = nil }
        }
    }

    private func hideListing() async {
        guard let pid = report.productId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let r = try await PreluraAdminAPI.flagProduct(
                client: session.graphQL,
                productId: String(pid),
                reason: "COMMUNITY_GUIDELINES",
                flagType: "HIDDEN",
                notes: "Staff hide from \(report.id)"
            )
            if r.success == true {
                feedbackTitle = "Done"
                feedbackMessage = r.message ?? "Listing hidden."
            } else {
                feedbackTitle = "Could not hide"
                feedbackMessage = r.message ?? "Unknown error."
            }
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }

    private func deleteListing() async {
        guard let pid = report.productId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            try await PreluraAdminAPI.deleteProduct(client: session.graphQL, productId: pid)
            feedbackTitle = "Done"
            feedbackMessage = "Listing deleted."
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }

    private func suspendAccount() async {
        guard let uid = reportedAccountUserId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let r = try await PreluraAdminAPI.adminSuspendUser(client: session.graphQL, userId: uid)
            if r.success == true {
                feedbackTitle = "Done"
                feedbackMessage = r.message ?? "Account suspended."
            } else {
                feedbackTitle = "Could not suspend"
                feedbackMessage = r.message ?? "Unknown error."
            }
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }

    private func banAccount() async {
        guard let uid = reportedAccountUserId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let r = try await PreluraAdminAPI.adminBanUser(client: session.graphQL, userId: uid)
            if r.success == true {
                feedbackTitle = "Done"
                feedbackMessage = r.message ?? "Account banned."
            } else {
                feedbackTitle = "Could not ban"
                feedbackMessage = r.message ?? "Unknown error."
            }
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }

    private func unsuspendAccount() async {
        guard let uid = reportedAccountUserId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let r = try await PreluraAdminAPI.adminUnsuspendUser(client: session.graphQL, userId: uid)
            if r.success == true {
                feedbackTitle = "Done"
                feedbackMessage = r.message ?? "Suspension cleared."
            } else {
                feedbackTitle = "Could not unsuspend"
                feedbackMessage = r.message ?? "Unknown error."
            }
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }

    private func unbanAccount() async {
        guard let uid = reportedAccountUserId else { return }
        actionBusy = true
        defer { actionBusy = false }
        do {
            let r = try await PreluraAdminAPI.adminUnbanUser(client: session.graphQL, userId: uid)
            if r.success == true {
                feedbackTitle = "Done"
                feedbackMessage = r.message ?? "Ban removed."
            } else {
                feedbackTitle = "Could not unban"
                feedbackMessage = r.message ?? "Unknown error."
            }
        } catch {
            feedbackTitle = "Error"
            feedbackMessage = error.localizedDescription
        }
    }
}

// MARK: - Same loader pattern as consumer `AdminReportOrderChatLoaderView`

private struct StaffReportConversationLoaderView: View {
    let conversationId: String
    @EnvironmentObject private var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var conversation: Conversation?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chat…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let conversation {
                ChatDetailView(conversation: conversation)
            } else {
                Text(errorMessage ?? "Could not open this conversation.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            chatService.updateAuthToken(authService.authToken)
            do {
                let loaded = try await chatService.getConversationById(
                    conversationId: conversationId,
                    currentUsername: authService.username
                )
                await MainActor.run {
                    conversation = loaded
                    isLoading = false
                    if loaded == nil {
                        errorMessage = "Not found or no permission for this chat."
                    }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
