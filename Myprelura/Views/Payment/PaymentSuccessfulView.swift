import SwiftUI

/// Payment success confirmation (Flutter PaymentSuccessfulScreen). Shows "Order Successful" and navigates after delay.
struct PaymentSuccessfulView: View {
    var productId: String?
    var onDismiss: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var hasNavigated = false

    var body: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 40) {
                Text("Order \nSuccessful")
                    .font(Theme.Typography.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .lineSpacing(4)

                Text("Your order has been placed!\nThanks for choosing sustainable fashion. 🌍✨")
                    .font(Theme.Typography.body)
                    .foregroundColor(.white)
                    .lineSpacing(6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.lg)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.primaryColor.opacity(0.9))
        .ignoresSafeArea()
        .onAppear {
            guard !hasNavigated else { return }
            hasNavigated = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                onDismiss?()
                dismiss()
            }
        }
    }
}

#Preview {
    PaymentSuccessfulView(productId: nil)
}
