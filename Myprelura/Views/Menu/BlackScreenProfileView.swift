import SwiftUI

/// Debug: copy of the profile page with a single custom background colour (hex) to compare how black/dark UI looks.
struct BlackScreenProfileView: View {
    let hex: String
    @State private var expandedCategories = false

    private var backgroundColor: Color { Color(hex: hex) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileSection
                bioSection
                userStatsSection
                filtersSection
                itemsGridPlaceholder
            }
        }
        .background(backgroundColor)
        .navigationTitle(hex)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Profile Section (placeholder)
    private var profileSection: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.primaryColor)
                .frame(width: 70, height: 70)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 35))
                        .foregroundColor(.white)
                )
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("username")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
                HStack(spacing: 2) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image(systemName: "star.fill")
                            .font(.system(size: 13))
                            .foregroundColor(.yellow)
                    }
                    Text("(12)")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.primaryColor)
                }
                Text("London, UK")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.primaryText)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "person.circle")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.primaryText)
                Image(systemName: "arrowshape.turn.up.left")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.primaryText)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var bioSection: some View {
        Text("Short bio placeholder. This is how body text reads on this background.")
            .font(Theme.Typography.subheadline)
            .foregroundColor(Theme.Colors.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
    }

    private var userStatsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.md) {
                StatColumn(value: "24", label: "Listings")
                StatColumn(value: "8", label: "Followings")
                StatColumn(value: "42", label: "Followers")
                StatColumn(value: "12", label: "Reviews")
                StatColumn(value: "UK", label: "Location")
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.md)
        .overlay(ContentDivider(), alignment: .bottom)
    }

    private var filtersSection: some View {
        VStack(spacing: 0) {
            Button(action: { withAnimation { expandedCategories.toggle() } }) {
                HStack {
                    Text("Categories")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.secondaryText)
                    Spacer()
                    Image(systemName: expandedCategories ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.toggle() }))

            if expandedCategories {
                VStack(spacing: 0) {
                    filterRow("Women", count: 5)
                    ContentDivider().padding(.leading, Theme.Spacing.lg)
                    filterRow("Men", count: 3)
                    ContentDivider().padding(.leading, Theme.Spacing.lg)
                    filterRow("Accessories", count: 2)
                }
                .overlay(ContentDivider(), alignment: .bottom)
            }

            HStack {
                Text("Multi-buy:")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
                Toggle("", isOn: .constant(true))
                    .tint(Theme.primaryColor)
                    .frame(width: 50)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
            .overlay(ContentDivider(), alignment: .bottom)

            HStack {
                Text("Top brands")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.secondaryText)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)

            HStack {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 14))
                    Text("Filter")
                        .font(Theme.Typography.subheadline)
                }
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassEffect(cornerRadius: Theme.Glass.cornerRadius)
                Spacer()
                HStack(spacing: Theme.Spacing.xs) {
                    Text("Newest First")
                        .font(Theme.Typography.subheadline)
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 12))
                }
                .foregroundColor(Theme.Colors.secondaryText)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .glassEffect(cornerRadius: Theme.Glass.cornerRadius)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private func filterRow(_ name: String, count: Int) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "minus")
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(name)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.primaryText)
            Text("(\(count) items)")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.secondaryText)
            Spacer(minLength: Theme.Spacing.md)
            Image(systemName: "square")
                .font(.system(size: 16))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var itemsGridPlaceholder: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: Theme.Spacing.sm),
                GridItem(.flexible(), spacing: Theme.Spacing.sm)
            ],
            spacing: Theme.Spacing.md
        ) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.Glass.cornerRadius)
                    .fill(Theme.Colors.secondaryBackground)
                    .aspectRatio(0.75, contentMode: .fit)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(Theme.Colors.secondaryText)
                    )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
    }
}
