import SwiftUI
import Shimmer

/// Full-screen profile shimmer matching ProfileView layout: nav bar, avatar 88 + stats row, stars, Categories / Multi-buy / Top brands / Filter-Sort, then product grid. Use when loading; hide navigation bar so this is the only content.
struct ProfileShimmerView: View {
    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    // Nav bar + title area
                    RoundedRectangle(cornerRadius: 0)
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(height: topInset + 44)
                        .frame(maxWidth: .infinity)
                        .ignoresSafeArea(edges: .top)

                    // Profile section: avatar 88 + stats row (matches profileSection)
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        HStack(alignment: .center, spacing: 0) {
                            Circle()
                                .fill(Theme.Colors.secondaryBackground)
                                .frame(width: 88, height: 88)
                            Spacer(minLength: Theme.Spacing.xl)
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(0..<3, id: \.self) { _ in
                                    VStack(spacing: 2) {
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Theme.Colors.secondaryBackground)
                                            .frame(width: 36, height: 18)
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(Theme.Colors.secondaryBackground)
                                            .frame(width: 50, height: 12)
                                    }
                                    .frame(minWidth: 50)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                            Spacer(minLength: Theme.Spacing.xl)
                        }
                        // Stars row
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Theme.Colors.secondaryBackground)
                                .frame(width: 80, height: 14)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)

                    // Divider then Categories row
                    Rectangle()
                        .fill(Theme.Colors.secondaryBackground.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.horizontal, Theme.Spacing.md)
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 80, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 12, height: 12)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)

                    // Multi-buy row
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 70, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 30, height: 14)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)

                    // Top brands row + pills
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 70, height: 14)
                        Spacer()
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 18, height: 18)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.sm) {
                            ForEach(0..<5, id: \.self) { _ in
                                RoundedRectangle(cornerRadius: Theme.Glass.tagCornerRadius)
                                    .fill(Theme.Colors.secondaryBackground)
                                    .frame(width: 80, height: 36)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                    }
                    .padding(.vertical, Theme.Spacing.sm)

                    // Filter / Sort row
                    HStack {
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 90, height: 36)
                        Spacer()
                        RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                            .fill(Theme.Colors.secondaryBackground)
                            .frame(width: 110, height: 36)
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)

                    // Product grid (matches itemsGridSection)
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: Theme.Spacing.sm),
                            GridItem(.flexible(), spacing: Theme.Spacing.sm)
                        ],
                        spacing: Theme.Spacing.md
                    ) {
                        ForEach(0..<6, id: \.self) { _ in
                            ProfileItemShimmer()
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .shimmering()
            }
            .scrollDisabled(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background.ignoresSafeArea(edges: .all))
    }
}

private struct ProfileItemShimmer: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.Colors.secondaryBackground)
                .aspectRatio(1.0/1.3, contentMode: .fit)
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
