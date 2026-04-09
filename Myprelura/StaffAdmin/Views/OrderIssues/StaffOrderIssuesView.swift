import SwiftUI

/// WEARHOUSE Pro: list all order issues; resolve pending disputes with refund / return / decline (GraphQL `adminResolveOrderIssue`).
struct StaffOrderIssuesView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @State private var issues: [StaffOrderIssueRow] = []
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { root }
            } else {
                root
            }
        }
    }

    private var root: some View {
        Group {
            if isLoading && issues.isEmpty {
                ProgressView("Loading issues…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if let loadError {
                        Text(loadError)
                            .font(Theme.Typography.footnote)
                            .foregroundStyle(Theme.Colors.error)
                    }
                    ForEach(sortedIssues) { row in
                        NavigationLink {
                            StaffOrderIssueDetailView(issue: row)
                        } label: {
                            StaffOrderIssueRowLabel(row: row)
                        }
                    }
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Order issues")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var sortedIssues: [StaffOrderIssueRow] {
        issues.sorted { a, b in
            let ap = (a.status ?? "").uppercased() == "PENDING"
            let bp = (b.status ?? "").uppercased() == "PENDING"
            if ap != bp { return ap && !bp }
            return (a.id) > (b.id)
        }
    }

    private func load() async {
        await MainActor.run {
            loadError = nil
            if issues.isEmpty { isLoading = true }
        }
        do {
            let rows = try await PreluraAdminAPI.allOrderIssues(client: session.graphQL)
            await MainActor.run {
                issues = rows
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = error.localizedDescription
            }
        }
    }
}

private struct StaffOrderIssueRowLabel: View {
    let row: StaffOrderIssueRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Issue #\(row.id)")
                    .font(Theme.Typography.headline)
                Spacer()
                Text((row.status ?? "—").uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusTint.opacity(0.2))
                    .foregroundStyle(statusTint)
                    .clipShape(Capsule())
            }
            if let oid = row.order?.id {
                Text("Order #\(oid)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Text("\(row.order?.user?.username ?? "buyer") → \(row.order?.seller?.username ?? "seller")")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(row.issueType ?? "Issue")
                .font(Theme.Typography.subheadline)
                .foregroundStyle(Theme.Colors.primaryText)
            if let d = row.description, !d.isEmpty {
                Text(d)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTint: Color {
        switch (row.status ?? "").uppercased() {
        case "PENDING": return .orange
        case "RESOLVED": return .green
        case "DECLINED": return .gray
        default: return Theme.primaryColor
        }
    }
}

struct StaffOrderIssueDetailView: View {
    let issue: StaffOrderIssueRow

    @Environment(\.dismiss) private var dismiss
    @Environment(AdminSession.self) private var session
    @State private var busy = false
    @State private var feedback: String?
    @State private var showRefundWithoutConfirm = false
    @State private var showRefundWithConfirm = false
    @State private var showDeclineConfirm = false
    @State private var returnPostagePayer = "SELLER"

    private var isPending: Bool {
        (issue.status ?? "").uppercased() == "PENDING"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                metaBlock
                if !isPending {
                    resolvedBlock
                }
                if let feedback {
                    Text(feedback)
                        .font(Theme.Typography.footnote)
                        .foregroundStyle(Theme.Colors.error)
                }
                if isPending {
                    pendingActions
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Issue #\(issue.id)")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Refund without return?",
            isPresented: $showRefundWithoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm refund (buyer keeps item)", role: .destructive) {
                Task { await resolve(status: "RESOLVED", resolution: "REFUND_WITHOUT_RETURN", postage: nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Records the resolution as refund without return. Payment processing may still run separately on the server.")
        }
        .confirmationDialog(
            "Refund with return?",
            isPresented: $showRefundWithConfirm,
            titleVisibility: .visible
        ) {
            Button("Confirm", role: .destructive) {
                Task {
                    await resolve(
                        status: "RESOLVED",
                        resolution: "REFUND_WITH_RETURN",
                        postage: returnPostagePayer
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                returnPostagePayer == "SELLER"
                    ? "Return postage will be recorded as seller pays."
                    : "Return postage will be recorded as buyer pays."
            )
        }
        .confirmationDialog(
            "Decline this issue?",
            isPresented: $showDeclineConfirm,
            titleVisibility: .visible
        ) {
            Button("Decline issue", role: .destructive) {
                Task { await resolve(status: "DECLINED", resolution: nil, postage: nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Marks the buyer’s case as declined by support.")
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if let pid = issue.publicId, !pid.isEmpty {
                Text("Public ID: \(pid)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Text(issue.issueType ?? "—")
                .font(Theme.Typography.title3)
            Text(issue.description ?? "No description")
                .font(Theme.Typography.body)
            if let raised = issue.raisedBy?.username {
                Text("Raised by @\(raised)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var resolvedBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Outcome")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text((issue.status ?? "—").uppercased())
                .font(Theme.Typography.headline)
            if let r = issue.resolution, !r.isEmpty {
                Text(r.replacingOccurrences(of: "_", with: " "))
                    .font(Theme.Typography.subheadline)
            }
            if let p = issue.returnPostagePaidBy, !p.isEmpty {
                Text("Return postage: \(p.lowercased())")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var pendingActions: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("Support actions")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showRefundWithoutConfirm = true
            } label: {
                labelButton(title: "Refund without return", subtitle: "Buyer keeps the item", busy: busy)
            }
            .buttonStyle(.plain)
            .disabled(busy)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Picker("Return postage", selection: $returnPostagePayer) {
                    Text("Seller pays return postage").tag("SELLER")
                    Text("Buyer pays return postage").tag("BUYER")
                }
                .pickerStyle(.segmented)
                Button {
                    showRefundWithConfirm = true
                } label: {
                    labelButton(title: "Refund with return", subtitle: "Buyer returns item before refund completes", busy: busy)
                }
                .buttonStyle(.plain)
                .disabled(busy)
            }

            Button {
                showDeclineConfirm = true
            } label: {
                labelButton(title: "Decline issue", subtitle: "Close case without a refund path", busy: busy, tone: .secondary)
            }
            .buttonStyle(.plain)
            .disabled(busy)
        }
    }

    private func labelButton(title: String, subtitle: String, busy: Bool, tone: PrimaryTone = .primary) -> some View {
        HStack {
            if busy {
                ProgressView()
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(tone == .primary ? Theme.primaryColor : Theme.Colors.primaryText)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private enum PrimaryTone {
        case primary
        case secondary
    }

    private func resolve(status: String, resolution: String?, postage: String?) async {
        await MainActor.run {
            busy = true
            feedback = nil
        }
        do {
            try await PreluraAdminAPI.adminResolveOrderIssue(
                client: session.graphQL,
                issueId: issue.id,
                status: status,
                resolution: resolution,
                returnPostagePaidBy: postage
            )
            await MainActor.run {
                busy = false
                dismiss()
            }
        } catch {
            await MainActor.run {
                busy = false
                feedback = error.localizedDescription
            }
        }
    }
}

// MARK: - Open issue resolver from Reports (id may match queue row or fall back to order id)

struct StaffOrderIssueDetailLoaderView: View {
    /// `allReports` backend id when it matches `allOrderIssues.id`.
    var preferredIssueId: Int
    var orderId: Int?

    @Environment(AdminSession.self) private var session
    @State private var issue: StaffOrderIssueRow?
    @State private var loadError: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading issue…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let issue {
                StaffOrderIssueDetailView(issue: issue)
            } else {
                Text(
                    loadError
                        ?? "This case was not found in the order-issues list. Use Reports → toolbar → Order issues and locate it there."
                )
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding()
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Resolve issue")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .task { await load() }
    }

    private func load() async {
        await MainActor.run {
            isLoading = true
            loadError = nil
        }
        do {
            let rows = try await PreluraAdminAPI.allOrderIssues(client: session.graphQL)
            let byId = rows.first { $0.id == preferredIssueId }
            let byOrder: StaffOrderIssueRow? = {
                guard let oid = orderId else { return nil }
                let key = String(oid)
                return rows.first { $0.order?.id == key }
            }()
            let chosen = byId ?? byOrder
            await MainActor.run {
                issue = chosen
                isLoading = false
                if chosen == nil {
                    loadError = "Could not match this report to an order issue row."
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                loadError = error.localizedDescription
            }
        }
    }
}
