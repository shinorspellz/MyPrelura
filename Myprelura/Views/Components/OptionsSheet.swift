import SwiftUI

/// Reusable modal sheet with title, close button, and consistent presentation. Use for product options, sort, filter, and similar modals.
/// For multiple related sheets (sort / filter / search), use one `.sheet(item:)` with an `Identifiable` enum; chaining several `.sheet(isPresented:)` on the same view stacks modals when more than one binding is true.
/// Matches Sort modal: one colour (Theme.Colors.modalSheetBackground) for nav bar and content area.
struct OptionsSheet<Content: View>: View {
    let title: String
    let onDismiss: () -> Void
    var detents: [PresentationDetent]
    /// When false, uses system default sheet corner radius (e.g. product Options modal).
    var useCustomCornerRadius: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var selectedDetent: PresentationDetent

    private var sheetBackground: Color { Theme.Colors.modalSheetBackground }

    init(
        title: String,
        onDismiss: @escaping () -> Void,
        /// Slightly above half-height so header + list are not cramped; user can still drag to `.large`.
        detents: [PresentationDetent] = [.fraction(0.58), .large],
        useCustomCornerRadius: Bool = true,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.onDismiss = onDismiss
        self.detents = detents
        self.useCustomCornerRadius = useCustomCornerRadius
        self.content = content
        _selectedDetent = State(initialValue: detents.first ?? .fraction(0.58))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Custom handle: avoids overlap with a centered title when using the system drag indicator
            // (fixed detents + `presentationBackground` often crowd the stock indicator into the header row).
            Capsule()
                .fill(Theme.Colors.secondaryText.opacity(0.35))
                .frame(width: 36, height: 5)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            HStack {
                Spacer()
                Text(title)
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.primaryText)
                Spacer()
            }
            .overlay(alignment: .trailing) {
                GlassIconButton(
                    icon: "xmark",
                    size: 36,
                    iconColor: Theme.Colors.primaryText,
                    iconSize: 15,
                    action: onDismiss
                )
                .padding(.trailing, Theme.Spacing.md)
            }
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.md)
            .layoutPriority(1)

            content()
                .frame(maxWidth: .infinity, alignment: .top)
                .layoutPriority(0)

            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Spacing.sm)
        .background(sheetBackground)
        .presentationDetents(Set(detents), selection: $selectedDetent)
        .presentationDragIndicator(.hidden)
        .presentationBackground(sheetBackground)
        .modifier(SheetCornerRadiusModifier(apply: useCustomCornerRadius))
    }
}

/// Applies presentation corner radius when available (iOS 16.4+). When apply is false, leaves system default (e.g. product Options sheet).
private struct SheetCornerRadiusModifier: ViewModifier {
    var apply: Bool = true
    func body(content: Content) -> some View {
        if apply, #available(iOS 16.4, *) {
            content.presentationCornerRadius(20)
        } else {
            content
        }
    }
}
