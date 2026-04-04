import SwiftUI
import Shimmer

/// Full-screen feed shimmer matching HomeView layout: logo area, search bar, category pills, 2-column grid. No forced minHeight so it doesn’t look zoomed out.
struct FeedShimmerView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Placeholder for nav/logo area (real nav is hidden when this shows)
            Color.clear
                .frame(height: 1)

            // Search bar (matches FeedSearchField: horizontal md, top xs, bottom xs)
            RoundedRectangle(cornerRadius: 30)
                .fill(Theme.Colors.secondaryBackground)
                .frame(height: 44)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.xs)

            // Category filters row (matches categoryFiltersSection)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(0..<5, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 60, height: 36)
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.sm)

            // Product grid (matches productGridSection: 2 columns, same padding)
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ],
                alignment: .leading,
                spacing: Theme.Spacing.md
            ) {
                ForEach(0..<6, id: \.self) { _ in
                    FeedItemShimmer()
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.md)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
        .shimmering()
    }
}

private struct FeedItemShimmer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.xs) {
                Circle()
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 20, height: 20)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 60, height: 12)
            }
            .padding(.horizontal, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.xs * 1.5)

            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.secondaryBackground)
                .aspectRatio(1.0 / 1.3, contentMode: .fit)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 50, height: 14)
                    .padding(.top, Theme.Spacing.sm)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 14)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 80, height: 12)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(width: 40, height: 14)
            }
            .padding(.horizontal, Theme.Spacing.xs)
        }
    }
}
