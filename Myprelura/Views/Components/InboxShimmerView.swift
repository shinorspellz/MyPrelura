import SwiftUI
import Shimmer

/// Full-screen Messages shimmer: matches ChatListView layout (nav bar, search bar, conversation rows). Use when loading; hide navigation bar so this is the only content.
struct InboxShimmerView: View {
    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            VStack(spacing: 0) {
                // Nav bar + title area (replaces system nav so title/search not visible)
                RoundedRectangle(cornerRadius: 0)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: topInset + 44)
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea(edges: .top)

                // Search bar (matches DiscoverSearchField: rounded, full width)
                RoundedRectangle(cornerRadius: 30)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 44)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.top, Theme.Spacing.xs)
                    .padding(.trailing, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.sm)

                // Conversation list (matches ChatRowView: avatar 50, name+time, message preview)
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { _ in
                        InboxRowShimmer()
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background.ignoresSafeArea(edges: .all))
            .shimmering()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One row matching ChatRowView: 50pt avatar, name + time on one line, message preview below.
private struct InboxRowShimmer: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.Colors.secondaryBackground)
                .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: 100, height: 16)
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.secondaryBackground)
                        .frame(width: 48, height: 12)
                }
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.secondaryBackground)
                    .frame(height: 14)
                    .frame(maxWidth: .infinity)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}
