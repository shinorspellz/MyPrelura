import SwiftUI
import UIKit

/// Minimal order shell so `OrderDetailView` can hydrate from `userOrders` like a deep link.
private func orderStubForHelpNavigation(id: String) -> Order {
    Order(
        id: id,
        publicId: nil,
        priceTotal: "0",
        discountPrice: nil,
        status: "",
        createdAt: Date(),
        otherParty: nil,
        products: [],
        shippingAddress: nil,
        shipmentService: nil,
        deliveryDate: nil,
        trackingNumber: nil,
        trackingUrl: nil,
        buyerOrderCountWithSeller: nil,
        cancellation: nil
    )
}

/// In-conversation order help menu (Flutter OrderHelpScreen).
struct OrderHelpView: View {
    var orderId: String?
    var conversationId: String?
    /// When set (e.g. multibuy), scopes help to that line item for support context and “item not as described” product load.
    var helpContextProduct: OrderProductSummary? = nil

    var body: some View {
        List {
            Section("Need help with your order?") {
                helpRow(
                    title: "Item Not as Described",
                    content: "If the item you received doesn't match the description, you can raise an issue within 3 days of delivery.",
                    destination: ItemNotAsDescribedHelpView(
                        orderId: orderId,
                        conversationId: conversationId,
                        relatedProductId: helpContextProduct?.id
                    )
                )

                if let oid = orderId, !oid.isEmpty {
                    helpRow(
                        title: "Order Status",
                        content: "Track your order status and see where your item is in the delivery process.",
                        destination: OrderDetailView(order: orderStubForHelpNavigation(id: oid), isSeller: nil, suppressBuyerHelpAndCancelActions: true)
                    )
                } else {
                    disabledHelpRow(
                        title: "Order Status",
                        content: "Track your order status and see where your item is in the delivery process.",
                        reason: "Order information is unavailable here."
                    )
                }

                if let oid = orderId, !oid.isEmpty {
                    helpRow(
                        title: "Tracking Information",
                        content: "View your tracking code if the seller has added one. You can copy it to check with the carrier.",
                        destination: OrderTrackingCodeHelpView(orderId: oid)
                    )
                } else {
                    disabledHelpRow(
                        title: "Tracking Information",
                        content: "View your tracking code if the seller has added one.",
                        reason: "Order information is unavailable here."
                    )
                }

                helpRow(
                    title: "Item Not Received",
                    content: "If you haven't received your item within the expected delivery window, read our guidance—then contact support if you still need help.",
                    destination: ItemNotReceivedGuidanceHelpView(
                        orderId: orderId,
                        conversationId: conversationId,
                        relatedProductId: helpContextProduct?.id
                    )
                )
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Help with Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func helpRow<D: View>(title: String, content: String, destination: D) -> some View {
        NavigationLink(destination: destination) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                Text(content)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(PlainTappableButtonStyle())
    }

    private func disabledHelpRow(title: String, content: String, reason: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.secondaryText)
            Text(content)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText.opacity(0.85))
            Text(reason)
                .font(Theme.Typography.footnote)
                .foregroundColor(Theme.Colors.secondaryText.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.xs)
    }
}

/// Shows tracking number from the live order (if any) with copy; otherwise explains it is not available.
private struct OrderTrackingCodeHelpView: View {
    let orderId: String

    @EnvironmentObject private var authService: AuthService
    @State private var trackingNumber: String?
    @State private var loading = true
    @State private var loadError: String?
    @State private var copiedToast = false

    private let userService = UserService()

    var body: some View {
        Group {
            if loading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let loadError, !loadError.isEmpty {
                Text(loadError)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(Theme.Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Text("Use this code with your carrier’s website or app. If nothing appears, the seller may not have added tracking yet.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    if let code = trackingNumber, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        HStack(spacing: Theme.Spacing.md) {
                            Text(code)
                                .font(.system(size: 16, weight: .regular, design: .monospaced))
                                .foregroundColor(Theme.Colors.primaryText)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button {
                                UIPasteboard.general.string = code
                                copiedToast = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                                    copiedToast = false
                                }
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundStyle(Theme.primaryColor)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy tracking code")
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous))
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                            Image(systemName: "tray")
                                .font(.system(size: 28))
                                .foregroundStyle(Theme.primaryColor)
                            Text("Tracking isn’t available yet")
                                .font(Theme.Typography.headline)
                                .foregroundColor(Theme.Colors.primaryText)
                            Text("The seller hasn’t provided a tracking number for this order, or it hasn’t synced yet. Check again later, or message the seller from your order chat.")
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius, style: .continuous))
                    }
                }
                .padding(Theme.Spacing.md)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.Colors.background)
        .navigationTitle("Tracking Information")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            if copiedToast {
                Text("Copied")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Color.black.opacity(0.82))
                    .clipShape(Capsule())
                    .padding(.bottom, Theme.Spacing.xl)
            }
        }
        .task { await loadTracking() }
    }

    private func loadTracking() async {
        await MainActor.run {
            loading = true
            loadError = nil
        }
        userService.updateAuthToken(authService.authToken)
        do {
            async let soldTask = userService.getUserOrders(isSeller: true, pageNumber: 1, pageCount: 100)
            async let boughtTask = userService.getUserOrders(isSeller: false, pageNumber: 1, pageCount: 100)
            let sold = try await soldTask
            let bought = try await boughtTask
            let merged = sold.orders + bought.orders
            let match = merged.first(where: { $0.id == orderId })
            await MainActor.run {
                let raw = match?.trackingNumber?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                trackingNumber = raw.isEmpty ? nil : raw
                loading = false
            }
        } catch {
            await MainActor.run {
                loading = false
                loadError = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        OrderHelpView(orderId: nil, conversationId: nil)
    }
}
