import SwiftUI

/// Cancellation reason: display label and GraphQL enum value. Matches Flutter OrderCancellationReasonEnum.
enum OrderCancellationReason: String, CaseIterable {
    case wrongItem = "WRONG_ITEM"
    case notAsDescribed = "NOT_AS_DESCRIBED"
    case wrongSize = "WRONG_SIZE"
    case counterfeit = "COUNTERFEIT"
    case changedMyMind = "CHANGED_MY_MIND"
    case mistake = "MISTAKE"

    var displayName: String {
        switch self {
        case .wrongItem: return L10n.string("Seller sent me the wrong item")
        case .notAsDescribed: return L10n.string("Item was not as described")
        case .wrongSize: return L10n.string("Item was the wrong size")
        case .counterfeit: return L10n.string("Item seems counterfeit")
        case .changedMyMind: return L10n.string("I changed my mind")
        case .mistake: return L10n.string("I made a mistake")
        }
    }
}

/// Cancel order flow: reason, notes, submit. Matches Flutter cancel_an_order (cancelOrder API).
struct CancelOrderView: View {
    let order: Order
    var isSellerRequest: Bool = false
    var onCancelled: (() -> Void)? = nil

    @EnvironmentObject var authService: AuthService
    @Environment(\.dismiss) private var dismiss
    private let userService = UserService()

    /// Reasons for shipped (COMPLETED/DELIVERED) vs unshipped; Flutter shows different lists.
    private static let reasonsForShipped: [OrderCancellationReason] = [.notAsDescribed, .wrongSize, .counterfeit, .wrongItem, .changedMyMind]
    private static let reasonsForUnshipped: [OrderCancellationReason] = [.mistake, .changedMyMind]

    @State private var selectedReason: OrderCancellationReason?
    @State private var notes: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var displayedReasons: [OrderCancellationReason] {
        if order.status == "DELIVERED" || order.status == "COMPLETED" {
            return Self.reasonsForShipped
        }
        return Self.reasonsForUnshipped
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text(L10n.string("Choose a reason for cancelling"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)

                ForEach(displayedReasons, id: \.rawValue) { reason in
                    Button {
                        selectedReason = reason
                    } label: {
                        HStack {
                            Text(reason.displayName)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if selectedReason == reason {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.primaryColor)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .background(Theme.Colors.secondaryBackground)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius))
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }

                Text(L10n.string("Additional notes (required)"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                TextField(L10n.string("Describe the issue"), text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)

                if let err = errorMessage {
                    Text(err)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }

                Button {
                    Task { await submitCancel() }
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .tint(Theme.Colors.primaryText)
                    } else {
                        Text(isSellerRequest ? L10n.string("Send request") : L10n.string("Cancel order"))
                    }
                }
                .disabled(selectedReason == nil || notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSubmitting)
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryColor)
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle(isSellerRequest ? L10n.string("Request cancellation") : L10n.string("Cancel Order"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func submitCancel() async {
        guard let reason = selectedReason, let orderId = Int(order.id) else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        userService.updateAuthToken(authService.authToken)
        do {
            let notesTrimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if isSellerRequest {
                try await userService.sellerRequestOrderCancellation(orderId: orderId, reason: reason.rawValue, notes: notesTrimmed, imagesUrl: [])
            } else {
                try await userService.cancelOrder(orderId: orderId, reason: reason.rawValue, notes: notesTrimmed, imagesUrl: [])
            }
            await MainActor.run {
                onCancelled?()
                dismiss()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
