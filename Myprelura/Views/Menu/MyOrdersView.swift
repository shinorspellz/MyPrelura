import SwiftUI

/// My Orders: fetch Sold/Bought via userOrders, filter by All / In Progress / Cancelled / Completed. Matches Flutter my_order_screen.
struct MyOrdersView: View {
    @EnvironmentObject var authService: AuthService
    @State private var selectedTab: Int = 0
    @State private var selectedFilter: Int = 0
    @State private var soldOrders: [Order] = []
    @State private var boughtOrders: [Order] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private let tabs = ["Sold", "Bought"]
    private let filters = ["All", "In Progress", "Cancelled", "Completed"]
    private let userService = UserService()

    private var isSold: Bool { selectedTab == 0 }
    private var currentOrders: [Order] { isSold ? soldOrders : boughtOrders }
    private var filteredOrders: [Order] {
        let list = currentOrders
        switch filters[selectedFilter] {
        case "All": return list
        case "In Progress": return list.filter { ["CONFIRMED", "SHIPPED"].contains($0.status) }
        case "Cancelled": return list.filter { ["CANCELLED", "REFUNDED"].contains($0.status) }
        case "Completed": return list.filter { $0.status == "DELIVERED" }
        default: return list
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $selectedTab) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    Text(tabs[i]).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(Theme.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<filters.count, id: \.self) { i in
                        PillTag(
                            title: filters[i],
                            isSelected: selectedFilter == i,
                            accentWhenUnselected: false,
                            action: { selectedFilter = i }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.bottom, Theme.Spacing.sm)

            if let err = errorMessage {
                Text(err)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.error)
                    .padding(.horizontal)
            }

            if isLoading && soldOrders.isEmpty && boughtOrders.isEmpty {
                Spacer()
                ProgressView()
                Spacer()
            } else if filteredOrders.isEmpty {
                Spacer()
                Text("No orders yet")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .padding(Theme.Spacing.xl)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(filteredOrders) { order in
                            NavigationLink(destination: OrderDetailView(order: order, isSeller: isSold)) {
                                OrderRowView(order: order, isSold: isSold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainTappableButtonStyle())
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.lg)
                }
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("My orders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private func load() async {
        userService.updateAuthToken(authService.authToken)
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let soldTask = userService.getUserOrders(isSeller: true)
            async let boughtTask = userService.getUserOrders(isSeller: false)
            let (soldResult, boughtResult) = try await (soldTask, boughtTask)
            await MainActor.run {
                soldOrders = soldResult.orders
                boughtOrders = boughtResult.orders
            }
        } catch {
            // Pull-to-refresh cancels the task when the gesture ends; don't show that as a red error.
            let isCancelled = (error as? CancellationError) != nil
                || (error as? URLError)?.code == .cancelled
                || error.localizedDescription.lowercased().contains("cancelled")
            await MainActor.run {
                errorMessage = isCancelled ? nil : error.localizedDescription
            }
        }
    }
}

// MARK: - Order row (thumbnail, title, other party, total, status)
private struct OrderRowView: View {
    let order: Order
    let isSold: Bool

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            orderImage
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(order.firstProductName ?? "Order")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .lineLimit(1)
                if let other = order.otherParty {
                    Text(isSold ? "Buyer: \(other.username)" : "Seller: \(other.username)")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                HStack {
                    Text("£\(order.priceTotal)")
                        .font(Theme.Typography.body)
                        .fontWeight(.medium)
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text(order.statusDisplay)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.primaryColor)
                }
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Glass.cornerRadius)
    }

    private var orderImage: some View {
        Group {
            if let url = order.firstProductImageUrl, !url.isEmpty {
                AsyncImage(url: URL(string: url)) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Rectangle().fill(Theme.Colors.tertiaryBackground)
                    }
                }
            } else {
                Rectangle()
                    .fill(Theme.Colors.tertiaryBackground)
                    .overlay(Image(systemName: "bag").foregroundColor(Theme.Colors.secondaryText))
            }
        }
        .frame(width: 56, height: 56)
        .clipped()
        .cornerRadius(8)
    }
}

// MARK: - Order helpers
extension Order {
    var firstProductName: String? { products.first?.name }
    var firstProductImageUrl: String? { products.first?.imageUrl }
    var statusDisplay: String {
        if let c = cancellation, c.status.uppercased() == "PENDING" {
            return "Cancellation pending"
        }
        switch status {
        case "CONFIRMED": return "Confirmed"
        case "SHIPPED": return "Shipped"
        case "DELIVERED": return "Completed"
        case "CANCELLED": return "Cancelled"
        case "REFUNDED": return "Refunded"
        default: return status
        }
    }
}
