import SwiftUI
import UIKit

/// Staff-only: all orders site-wide; tap a row for full detail and mark delivered.
struct AdminAllOrdersView: View {
    @EnvironmentObject var authService: AuthService
    @StateObject private var adminService = AdminService(client: GraphQLClient())

    @State private var rows: [AdminOrderListRow] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pageNumber = 1
    private let pageSize = 50

    var body: some View {
        Group {
            if isLoading && rows.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, rows.isEmpty {
                Text(errorMessage)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.error)
                    .multilineTextAlignment(.center)
                    .padding()
            } else {
                List {
                    ForEach(rows) { row in
                        NavigationLink {
                            AdminOrderAdminDetailView(orderId: Int(row.id) ?? 0, adminService: adminService)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.publicId ?? "Order #\(row.id)")
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.primaryText)
                                Text(row.status ?? "—")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                Text("\(row.user?.username ?? "—") → \(row.seller?.username ?? "—")")
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.secondaryText)
                                if let t = row.priceTotal {
                                    Text(Self.formatMoney(t))
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(Theme.Colors.secondaryText)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .background(Theme.Colors.background)
        .navigationTitle("Orders")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .refreshable { await load(reset: true) }
        .task {
            if let token = authService.authToken {
                adminService.updateAuthToken(token)
            }
            await load(reset: true)
        }
    }

    private func load(reset: Bool) async {
        if reset { await MainActor.run { pageNumber = 1 } }
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            let next = try await adminService.fetchAdminAllOrders(pageCount: pageSize, pageNumber: reset ? 1 : pageNumber)
            await MainActor.run {
                rows = next
                isLoading = false
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private static func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "GBP"
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Detail

struct AdminOrderAdminDetailView: View {
    let orderId: Int
    @ObservedObject var adminService: AdminService

    @State private var order: AdminOrderDetailSnapshot?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isMarkingDelivered = false
    @State private var banner: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if let errorMessage, order == nil {
                Text(errorMessage)
                    .foregroundColor(Theme.Colors.error)
                    .padding()
            } else if let order {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if let banner {
                            Text(banner)
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .padding(.bottom, 4)
                        }
                        detailContent(order)
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let o = order, o.status != "DELIVERED", o.status != "CANCELLED" {
                ToolbarItem(placement: .primaryAction) {
                    Button("Mark delivered") {
                        Task { await markDelivered() }
                    }
                    .disabled(isMarkingDelivered)
                }
            }
        }
        .task {
            await reload()
        }
    }

    private func reload() async {
        await MainActor.run { isLoading = true; errorMessage = nil; banner = nil }
        do {
            let o = try await adminService.fetchAdminOrder(orderId: orderId)
            await MainActor.run {
                order = o
                isLoading = false
                if o == nil {
                    errorMessage = "Order not found."
                }
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func markDelivered() async {
        isMarkingDelivered = true
        banner = nil
        do {
            let result = try await adminService.adminMarkOrderDelivered(orderId: orderId)
            await MainActor.run {
                isMarkingDelivered = false
                banner = result.message ?? (result.success ? "Marked delivered." : "Failed.")
            }
            if result.success {
                await reload()
            }
        } catch {
            await MainActor.run {
                isMarkingDelivered = false
                banner = error.localizedDescription
            }
        }
    }

    @ViewBuilder
    private func detailContent(_ order: AdminOrderDetailSnapshot) -> some View {
        Group {
            if let s = order.publicId, !s.isEmpty { clickableLabeled("Public ID", s) }
            if let s = order.status { clickableLabeled("Status", s) }
            if let ca = order.createdAt, !ca.isEmpty {
                clickableLabeled("Placed", Self.formatAdminDate(iso: ca))
            }
            if let ua = order.updatedAt, !ua.isEmpty {
                clickableLabeled("Updated", Self.formatAdminDate(iso: ua))
            }
            clickableLabeled("Buyer", order.user?.username ?? "—")
            clickableLabeled("Seller", order.seller?.username ?? "—")
            if let st = order.itemsSubtotal { clickableLabeled("Items subtotal", Self.formatMoney(st)) }
            if let fee = order.buyerProtectionFee { clickableLabeled("Buyer protection", Self.formatMoney(fee)) }
            if let ship = order.shippingFee { clickableLabeled("Shipping", Self.formatMoney(ship)) }
            if let disc = order.discountPrice, disc > 0 { clickableLabeled("Discount", Self.formatMoney(disc)) }
            if let total = order.priceTotal { clickableLabeled("Total", Self.formatMoney(total)) }
            if let offer = order.offer {
                clickableLabeled("Offer", "\(offer.id ?? "—") · \(offer.status ?? "—")")
            }
            if let addr = order.shippingAddressJson, !addr.isEmpty { clickableLabeled("Shipping (JSON)", addr) }
            if let tn = order.trackingNumber, !tn.isEmpty { clickableLabeled("Tracking #", tn) }
            if let tu = order.trackingUrl, !tu.isEmpty { clickableLabeled("Tracking URL", tu) }
            if let cn = order.carrierName, !cn.isEmpty { clickableLabeled("Carrier", cn) }
            if let sl = order.shippingLabelUrl, !sl.isEmpty { clickableLabeled("Label URL", sl) }
            if let es = order.shipmentEstimatedDelivery, !es.isEmpty { clickableLabeled("Est. delivery", es) }
            if let ad = order.shipmentActualDelivery, !ad.isEmpty { clickableLabeled("Actual delivery", ad) }
            if let ss = order.shipmentInternalStatus, !ss.isEmpty { clickableLabeled("Shipment status", ss) }
            if let svc = order.shipmentService, !svc.isEmpty { clickableLabeled("Shipping service", svc) }

            if let items = order.lineItems, !items.isEmpty {
                Text("Line items")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                ForEach(items) { li in
                    let name = li.productName ?? "Product #\(li.productId.map(String.init) ?? "?")"
                    let price = li.priceAtPurchase.map(Self.formatMoney) ?? "—"
                    clickableLabeled(name, price)
                }
            }
            if let pays = order.payments, !pays.isEmpty {
                Text("Payments")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                ForEach(pays) { p in
                    let ref = p.paymentRef ?? "—"
                    let st = p.paymentStatus ?? "—"
                    let amt = p.paymentAmount.map(Self.formatMoney) ?? "—"
                    clickableLabeled("Payment \(ref)", "\(st) · \(amt)")
                    if let pi = p.paymentIntentId, !pi.isEmpty { clickableLabeled("Intent", pi) }
                }
            }
            if let refs = order.refunds, !refs.isEmpty {
                Text("Refunds / returns")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                ForEach(refs) { r in
                    let amt = r.refundAmount.map(Self.formatMoney) ?? "—"
                    let st = r.status ?? "—"
                    clickableLabeled("Refund #\(r.id)", "\(st) · \(amt)")
                }
            }
            if let tl = order.statusTimeline, !tl.isEmpty {
                Text("Timeline")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                ForEach(tl) { ev in
                    let t = ev.createdAt.map { Self.formatAdminDate(iso: $0) } ?? "—"
                    clickableLabeled(ev.status ?? "—", t)
                }
            }
            if let c = order.cancelledOrder {
                Text("Cancellation")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                if let r = c.buyerCancellationReason { clickableLabeled("Buyer reason", r) }
                if let s = c.sellerResponse { clickableLabeled("Seller response", s) }
                if let st = c.status { clickableLabeled("Cancel status", st) }
                if let n = c.notes, !n.isEmpty { clickableLabeled("Notes", n) }
            }
            if let oc = order.orderConversationId {
                clickableLabeled("Order chat ID", String(oc))
            }
        }
    }

    private func clickableLabeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            if value.lowercased().hasPrefix("http://") || value.lowercased().hasPrefix("https://"),
               let url = URL(string: value) {
                Link(value, destination: url)
                    .font(Theme.Typography.body)
            } else {
                Text(value)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Copy") {
                UIPasteboard.general.string = value
            }
        }
    }

    private static func formatAdminDate(iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var d = f.date(from: iso)
        if d == nil {
            f.formatOptions = [.withInternetDateTime]
            d = f.date(from: iso)
        }
        guard let date = d else { return iso }
        let out = DateFormatter()
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: date)
    }

    private static func formatMoney(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "GBP"
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
