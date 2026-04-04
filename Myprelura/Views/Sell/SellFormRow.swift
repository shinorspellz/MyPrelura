import SwiftUI

/// Single form row for the Sell screen (matches Flutter MenuCard).
/// Title and optional value with chevron; use inside NavigationLink and add divider overlay in parent.
struct SellFormRow: View {
    let title: String
    let value: String?
    /// When true, title and value use secondary (grey) styling like unset fields (e.g. Discount Price).
    let preferSecondaryStyle: Bool

    init(title: String, value: String? = nil, preferSecondaryStyle: Bool = false) {
        self.title = title
        self.value = value
        self.preferSecondaryStyle = preferSecondaryStyle
    }

    private var useSecondaryStyle: Bool {
        preferSecondaryStyle || (value == nil || (value?.isEmpty ?? true))
    }

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Typography.body)
                .foregroundColor(useSecondaryStyle ? Theme.Colors.secondaryText : Theme.Colors.primaryText)

            Spacer()

            if let v = value, !v.isEmpty {
                Text(v)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13))
                .foregroundColor(Theme.Colors.secondaryText)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .contentShape(Rectangle())
    }
}
