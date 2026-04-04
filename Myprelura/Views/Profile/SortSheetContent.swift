import SwiftUI

/// Reusable sort options content for OptionsSheet (profile sort and offer-modal replacement). Use inside OptionsSheet or any sheet with same layout.
struct SortSheetContent: View {
    @Binding var selectedSort: ProfileSortOption
    var onApply: () -> Void

    private var optionDivider: some View {
        Rectangle()
            .fill(Theme.Colors.glassBorder)
            .frame(height: 0.5)
            .padding(.horizontal, Theme.Spacing.md)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(ProfileSortOption.allCases.enumerated()), id: \.offset) { index, option in
                Button(action: { selectedSort = option }) {
                    HStack {
                        Text(L10n.string(option.rawValue))
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                        Spacer()
                        if selectedSort == option {
                            Image(systemName: "checkmark")
                                .foregroundColor(Theme.primaryColor)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.md)
                }
                .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.selection() }))
                if index < ProfileSortOption.allCases.count - 1 { optionDivider }
            }
            optionDivider
            VStack(spacing: Theme.Spacing.sm) {
                BorderGlassButton(L10n.string("Clear")) {
                    selectedSort = .relevance
                }
                PrimaryGlassButton(L10n.string("Apply"), action: onApply)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.md)
            .padding(.bottom, Theme.Spacing.md)
        }
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
