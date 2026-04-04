import SwiftUI

struct TransactionsView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session
    @State private var rows: [AdminOrderRow] = []
    @State private var total = 0
    @State private var page = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    private let pageSize = 25

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { ordersRoot }
            } else {
                ordersRoot
            }
        }
    }

    private var ordersRoot: some View {
        List {
            Section {
                Text("Staff-wide order ledger (`adminAllOrders`). Use this for stuck-payment investigations and payout checks.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(Theme.Colors.error)
            }
            ForEach(rows) { o in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Order \(o.id)")
                            .font(Theme.Typography.headline)
                        Spacer()
                        Text(o.priceTotal.display)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.primaryColor)
                    }
                    Text(o.status ?? "—")
                        .font(Theme.Typography.subheadline)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("Buyer: @\(o.user?.username ?? "—")")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                    if let d = o.createdAt {
                        Text(d)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    }
                }
                .padding(.vertical, 4)
            }
            if rows.count < total {
                Button("Load more") {
                    Task { await loadMore() }
                }
                .disabled(isLoading)
            }
        }
        .navigationTitle("Transactions")
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        page = 1
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let r = try await PreluraAdminAPI.adminOrdersPage(client: session.graphQL, page: 1, pageSize: pageSize)
            rows = r.rows
            total = r.total
            page = 2
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMore() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let r = try await PreluraAdminAPI.adminOrdersPage(client: session.graphQL, page: page, pageSize: pageSize)
            rows.append(contentsOf: r.rows)
            total = r.total
            page += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
