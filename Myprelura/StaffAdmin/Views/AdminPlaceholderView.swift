import SwiftUI

/// Phase 2+ screens from the product spec: visible on iPad/Mac sidebar so the roadmap matches your checklist.
struct AdminPlaceholderView: View {
    let title: String
    let detail: String
    var systemImage: String = "hammer.fill"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.primaryColor)
                Text(title)
                    .font(Theme.Typography.title2)
                    .foregroundStyle(Theme.Colors.primaryText)
                Text(detail)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.lg)
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle(title)
        .adminNavigationChrome()
    }
}
