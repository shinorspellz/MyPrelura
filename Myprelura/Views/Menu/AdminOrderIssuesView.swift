import SwiftUI

/// Staff-only list of all order issues; expand for details and open persisted support chat.
struct AdminOrderIssuesView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var adminService = AdminService(client: GraphQLClient())

    @State private var issues: [AdminOrderIssueRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var expandedIds: Set<Int> = []

    @State private var replySheetIssue: AdminOrderIssueRow?
    @State private var actionSheetIssue: AdminOrderIssueRow?
    @State private var actionStatus: String = "RESOLVED"
    @State private var actionResolution: String = "REFUND_WITHOUT_RETURN"
    @State private var isSubmittingAction = false
    @State private var actionResultMessage: String?

    var body: some View {
        Group {
            if isLoading && issues.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, issues.isEmpty {
                Text(errorMessage)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    ForEach(issues) { issue in
                        DisclosureGroup(
                            isExpanded: Binding(
                                get: { expandedIds.contains(issue.id) },
                                set: { on in
                                    if on { expandedIds.insert(issue.id) } else { expandedIds.remove(issue.id) }
                                }
                            ),
                            content: {
                                issueDetail(issue)
                            },
                            label: {
                                HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(issue.publicId ?? "Issue #\(issue.id)")
                                            .font(Theme.Typography.headline)
                                            .foregroundColor(Theme.Colors.primaryText)
                                        Text(issue.issueType ?? "—")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        Text("Raised by \(issue.raisedBy?.username ?? "—")")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                        if let created = issue.createdAt, !created.isEmpty {
                                            Text(Self.formatAdminRelativeDate(iso: created))
                                                .font(Theme.Typography.caption)
                                                .foregroundColor(Theme.Colors.secondaryText)
                                        }
                                    }
                                    Spacer()
                                    if let orderCid = issue.order?.orderConversationId {
                                        NavigationLink {
                                            AdminStaffChatLoaderView(conversationId: String(orderCid))
                                        } label: {
                                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                                .foregroundColor(Theme.primaryColor)
                                                .imageScale(.medium)
                                                .accessibilityLabel("Open order chat")
                                        }
                                        .buttonStyle(PlainTappableButtonStyle())
                                    } else {
                                        Text("No order chat")
                                            .font(Theme.Typography.caption)
                                            .foregroundColor(Theme.Colors.secondaryText)
                                    }
                                }
                            }
                        )
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Order issues")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task {
            if let token = authService.authToken {
                adminService.updateAuthToken(token)
            }
            await load()
        }
        .sheet(item: $replySheetIssue) { issue in
            replyViaChatSheet(issue)
        }
        .sheet(item: $actionSheetIssue) { issue in
            takeActionSheet(issue)
        }
    }

    @ViewBuilder
    private func replyViaChatSheet(_ issue: AdminOrderIssueRow) -> some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose where to reply. Help chat rows are separate Prelura support threads for the buyer and/or seller (only shown if that person has started support). Order chat is the buyer ↔ seller sale thread.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .listRowBackground(Color.clear)
                }
                if let cid = issue.supportConversationId, let name = issue.order?.user?.username, !name.isEmpty {
                    NavigationLink {
                        HelpChatView(
                            orderId: issue.order?.id,
                            conversationId: String(cid),
                            issueDraft: supportIssueDraft(from: issue),
                            isAdminSupportThread: true,
                            customerUsername: name
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Help chat (\(name))")
                                .font(Theme.Typography.body.weight(.semibold))
                            Text("Conversation #\(cid)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                }
                if let cid = issue.sellerSupportConversationId, let name = issue.order?.seller?.username, !name.isEmpty {
                    NavigationLink {
                        HelpChatView(
                            orderId: issue.order?.id,
                            conversationId: String(cid),
                            issueDraft: supportIssueDraft(from: issue),
                            isAdminSupportThread: true,
                            customerUsername: name
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Help chat for (\(name))")
                                .font(Theme.Typography.body.weight(.semibold))
                            Text("Conversation #\(cid)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                }
                if let orderCid = issue.order?.orderConversationId {
                    NavigationLink {
                        AdminStaffChatLoaderView(conversationId: String(orderCid))
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Order chat (buyer & seller)")
                                .font(Theme.Typography.body.weight(.semibold))
                            Text("Conversation #\(orderCid)")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                        }
                    }
                }
                if issue.supportConversationId == nil && issue.sellerSupportConversationId == nil && issue.order?.orderConversationId == nil {
                    Text("No chat threads linked to this issue yet.")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            .navigationTitle("Reply via chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { replySheetIssue = nil }
                }
            }
        }
        .environmentObject(authService)
    }

    @ViewBuilder
    private func takeActionSheet(_ issue: AdminOrderIssueRow) -> some View {
        NavigationStack {
            Form {
                Section {
                    Picker("New status", selection: $actionStatus) {
                        Text("Resolved").tag("RESOLVED")
                        Text("Declined").tag("DECLINED")
                        Text("Reopen (pending)").tag("PENDING")
                    }
                    if actionStatus == "RESOLVED" {
                        Picker("Resolution (optional)", selection: $actionResolution) {
                            Text("None / note only").tag("")
                            Text("Refund without return").tag("REFUND_WITHOUT_RETURN")
                            Text("Refund with return").tag("REFUND_WITH_RETURN")
                        }
                    }
                } footer: {
                    Text("Seller-facing refunds still go through payment ops; this updates the case status for the app.")
                }
                if let actionResultMessage {
                    Section {
                        Text(actionResultMessage)
                            .font(Theme.Typography.caption)
                    }
                }
                Section {
                    Button {
                        Task { await submitAdminAction(for: issue) }
                    } label: {
                        if isSubmittingAction {
                            ProgressView()
                        } else {
                            Text("Apply")
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(isSubmittingAction)
                }
            }
            .navigationTitle("Take action")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        actionSheetIssue = nil
                        actionResultMessage = nil
                    }
                }
            }
            .onAppear {
                actionResultMessage = nil
                actionStatus = "RESOLVED"
                actionResolution = "REFUND_WITHOUT_RETURN"
            }
        }
    }

    @ViewBuilder
    private func issueDetail(_ issue: AdminOrderIssueRow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            labeled("Status", issue.status ?? "—")
            if let r = issue.resolution, !r.isEmpty {
                labeled("Resolution", r)
            }
            if let rb = issue.resolvedBy?.username, !rb.isEmpty {
                labeled("Resolved by", rb)
            }
            if let ra = issue.resolvedAt, !ra.isEmpty {
                labeled("Resolved at", Self.formatAdminDate(iso: ra))
            }
            labeled("Order ID", issue.order?.id ?? "—")
            if let created = issue.createdAt, !created.isEmpty {
                labeled("Issue created", Self.formatAdminDate(iso: created))
            }
            if let u = issue.updatedAt, !u.isEmpty {
                labeled("Issue updated", Self.formatAdminDate(iso: u))
            }

            orderDetailBlock(issue.order)

            Text("Description")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Text(issue.description ?? "—")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)

            if let urls = issue.imagesUrl, !urls.isEmpty {
                Text("Images")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
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
                                .frame(width: 72, height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    replySheetIssue = issue
                } label: {
                    Text("Reply via chat")
                        .font(Theme.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.primaryColor.opacity(0.15))
                        .foregroundColor(Theme.primaryColor)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PlainTappableButtonStyle())

                Button {
                    actionSheetIssue = issue
                } label: {
                    Text("Take action")
                        .font(Theme.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.Colors.secondaryBackground)
                        .foregroundColor(Theme.Colors.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(PlainTappableButtonStyle())
            }
            .padding(.top, Theme.Spacing.xs)

            if let cid = issue.supportConversationId, let name = issue.order?.user?.username, !name.isEmpty {
                NavigationLink {
                    HelpChatView(
                        orderId: issue.order?.id,
                        conversationId: String(cid),
                        issueDraft: supportIssueDraft(from: issue),
                        isAdminSupportThread: true,
                        customerUsername: name
                    )
                } label: {
                    Text("Help chat (\(name))")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundColor(Theme.primaryColor)
                }
            }
            if let cid = issue.sellerSupportConversationId, let name = issue.order?.seller?.username, !name.isEmpty {
                NavigationLink {
                    HelpChatView(
                        orderId: issue.order?.id,
                        conversationId: String(cid),
                        issueDraft: supportIssueDraft(from: issue),
                        isAdminSupportThread: true,
                        customerUsername: name
                    )
                } label: {
                    Text("Help chat for (\(name))")
                        .font(Theme.Typography.body.weight(.semibold))
                        .foregroundColor(Theme.primaryColor)
                }
            }
            if issue.supportConversationId == nil && issue.sellerSupportConversationId == nil {
                Text("No help chats yet (buyer must submit from Item not as described, or seller “Contact support”).")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    @ViewBuilder
    private func orderDetailBlock(_ order: AdminOrderDetailSnapshot?) -> some View {
        if let order {
            orderDetailContent(order)
        } else {
            Text("No order payload")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
    }

    @ViewBuilder
    private func orderDetailContent(_ order: AdminOrderDetailSnapshot) -> some View {
        Group {
            Text("Order details")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.top, Theme.Spacing.xs)

            if let s = order.status { labeled("Order status", s) }
            if let ca = order.createdAt, !ca.isEmpty {
                labeled("Order placed", Self.formatAdminDate(iso: ca))
            }
            if let ua = order.updatedAt, !ua.isEmpty {
                labeled("Order updated", Self.formatAdminDate(iso: ua))
            }
            labeled("Buyer", order.user?.username ?? "—")
            labeled("Seller", order.seller?.username ?? "—")

            if let st = order.itemsSubtotal {
                labeled("Items subtotal", Self.formatMoney(st))
            }
            if let fee = order.buyerProtectionFee {
                labeled("Buyer protection fee", Self.formatMoney(fee))
            }
            if let ship = order.shippingFee {
                labeled("Shipping fee", Self.formatMoney(ship))
            }
            if let disc = order.discountPrice, disc > 0 {
                labeled("Discount", Self.formatMoney(disc))
            }
            if let total = order.priceTotal {
                labeled("Total (stored on order)", Self.formatMoney(total))
            }

            if let offer = order.offer {
                let oid = offer.id ?? "—"
                let st = offer.status ?? "—"
                labeled("Linked offer", "\(oid) · \(st)")
            }

            if let addr = order.shippingAddressJson, !addr.isEmpty {
                labeled("Shipping address (JSON)", addr)
            }

            if let tn = order.trackingNumber, !tn.isEmpty { labeled("Tracking #", tn) }
            if let tu = order.trackingUrl, !tu.isEmpty { labeled("Tracking URL", tu) }
            if let cn = order.carrierName, !cn.isEmpty { labeled("Carrier", cn) }
            if let sl = order.shippingLabelUrl, !sl.isEmpty { labeled("Label URL", sl) }
            if let es = order.shipmentEstimatedDelivery, !es.isEmpty {
                labeled("Est. delivery", es)
            }
            if let ad = order.shipmentActualDelivery, !ad.isEmpty {
                labeled("Actual delivery", ad)
            }
            if let ss = order.shipmentInternalStatus, !ss.isEmpty {
                labeled("Shipment status", ss)
            }
            if let svc = order.shipmentService, !svc.isEmpty {
                labeled("Shipping service", svc)
            }

            if let items = order.lineItems, !items.isEmpty {
                Text("Line items")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, 4)
                ForEach(items) { li in
                    let name = li.productName ?? "Product #\(li.productId.map(String.init) ?? "?")"
                    let price = li.priceAtPurchase.map(Self.formatMoney) ?? "—"
                    labeled(name, price)
                }
            }

            if let pays = order.payments, !pays.isEmpty {
                Text("Payments")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, 4)
                ForEach(pays) { p in
                    let ref = p.paymentRef ?? "—"
                    let st = p.paymentStatus ?? "—"
                    let amt = p.paymentAmount.map(Self.formatMoney) ?? "—"
                    let created = p.createdAt.map { Self.formatAdminDate(iso: $0) } ?? ""
                    labeled("Payment \(ref)", "\(st) · \(amt)\(created.isEmpty ? "" : " · \(created)")")
                    if let pi = p.paymentIntentId, !pi.isEmpty {
                        labeled("Intent", pi)
                    }
                }
            }

            if let refs = order.refunds, !refs.isEmpty {
                Text("Refunds")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, 4)
                ForEach(refs) { r in
                    let amt = r.refundAmount.map(Self.formatMoney) ?? "—"
                    let st = r.status ?? "—"
                    labeled("Refund #\(r.id)", "\(st) · \(amt)")
                }
            }

            if let tl = order.statusTimeline, !tl.isEmpty {
                Text("Status timeline")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, 4)
                ForEach(tl) { ev in
                    let t = ev.createdAt.map { Self.formatAdminDate(iso: $0) } ?? "—"
                    labeled(ev.status ?? "—", t)
                }
            }

            if let c = order.cancelledOrder {
                Text("Cancellation")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(.top, 4)
                if let r = c.buyerCancellationReason { labeled("Buyer reason", r) }
                if let s = c.sellerResponse { labeled("Seller response", s) }
                if let st = c.status { labeled("Cancel status", st) }
                if let n = c.notes, !n.isEmpty { labeled("Notes", n) }
            }

            if let oc = order.orderConversationId {
                labeled("Order conversation ID", String(oc))
            }
        }
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
                .textSelection(.enabled)
        }
    }

    private func supportIssueDraft(from issue: AdminOrderIssueRow) -> SupportIssueDraft {
        let issueType = (issue.issueType ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (issue.description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return SupportIssueDraft(
            selectedOptions: issueType.isEmpty ? [] : [issueType],
            description: description,
            imageDatas: [],
            imageUrls: issue.imagesUrl ?? [],
            issueTypeCode: issue.issueType,
            issueId: issue.id,
            issuePublicId: issue.publicId
        )
    }

    private func submitAdminAction(for issue: AdminOrderIssueRow) async {
        await MainActor.run {
            isSubmittingAction = true
            actionResultMessage = nil
        }
        if let token = authService.authToken {
            adminService.updateAuthToken(token)
        }
        let resolution: String? = actionStatus == "RESOLVED" && !actionResolution.isEmpty ? actionResolution : nil
        do {
            let result = try await adminService.adminResolveOrderIssue(
                issueId: issue.id,
                status: actionStatus,
                resolution: resolution
            )
            await MainActor.run {
                isSubmittingAction = false
                actionResultMessage = result.success
                    ? (result.message ?? "Saved.")
                    : (result.message ?? "Failed.")
                if result.success {
                    Task {
                        await load()
                    }
                }
            }
        } catch {
            await MainActor.run {
                isSubmittingAction = false
                actionResultMessage = error.localizedDescription
            }
        }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }
        do {
            let list = try await adminService.fetchAllOrderIssues()
            await MainActor.run {
                issues = list
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func formatAdminDate(iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            let f3 = ISO8601DateFormatter()
            f3.formatOptions = [.withFullDate]
            return [f1, f2, f3]
        }()
        for p in parsers {
            if let d = p.date(from: iso) {
                let out = DateFormatter()
                out.dateStyle = .medium
                out.timeStyle = .short
                return out.string(from: d)
            }
        }
        return iso
    }

    private static func formatAdminRelativeDate(iso: String) -> String {
        let parsers: [ISO8601DateFormatter] = {
            let f1 = ISO8601DateFormatter()
            f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let f2 = ISO8601DateFormatter()
            f2.formatOptions = [.withInternetDateTime]
            let f3 = ISO8601DateFormatter()
            f3.formatOptions = [.withFullDate]
            return [f1, f2, f3]
        }()
        guard let date = parsers.compactMap({ $0.date(from: iso) }).first else {
            return formatAdminDate(iso: iso)
        }
        let now = Date()
        if now.timeIntervalSince(date) < 60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let value = formatter.localizedString(for: date, relativeTo: now)
        if value.lowercased().hasPrefix("in ") {
            return formatAdminDate(iso: iso)
        }
        return value
    }

    private static func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "GBP"
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }
}

// MARK: - Sheet item identity

extension AdminOrderIssueRow: Hashable {
    static func == (lhs: AdminOrderIssueRow, rhs: AdminOrderIssueRow) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Loads buyer–seller order conversation for staff (GraphQL `conversationById`).
private struct AdminStaffChatLoaderView: View {
    let conversationId: String
    @EnvironmentObject var authService: AuthService
    @StateObject private var chatService = ChatService()
    @State private var conversation: Conversation?
    @State private var errorMessage: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading chat…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let c = conversation {
                ChatDetailView(conversation: c)
            } else {
                Text(errorMessage ?? "Could not open this conversation.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if let token = authService.authToken {
                chatService.updateAuthToken(token)
            }
            do {
                let c = try await chatService.getConversationById(
                    conversationId: conversationId,
                    currentUsername: authService.username
                )
                await MainActor.run {
                    conversation = c
                    isLoading = false
                    if c == nil {
                        errorMessage = "Not found or no permission (deploy backend with staff order-chat access)."
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
