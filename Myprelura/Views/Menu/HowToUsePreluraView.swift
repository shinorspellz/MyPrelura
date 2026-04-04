import SwiftUI

/// How to use Prelura (from Flutter AboutPrelura – empty onTap). Placeholder content until copy is finalised.
struct HowToUsePreluraView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("How to use Prelura")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                Text("Discover, buy and sell preloved fashion. Browse items, add to favourites, make offers and manage your orders from the app.")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationTitle("How to use Prelura")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
