import SwiftUI

struct RefundOrderView: View {
    var body: some View {
        ScrollView {
            Text("Request a refund. Content coming soon.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Refund")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
