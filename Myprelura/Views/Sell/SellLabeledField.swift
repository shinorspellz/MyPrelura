import SwiftUI

/// Sell form text field matching Flutter PreluraAuthTextField: label above, hint, theme colors.
/// Label/hint use Theme.Colors.secondaryText (grey); input uses Theme.Colors.primaryText.
struct SellLabeledField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var minLines: Int = 1
    var maxLines: Int? = nil
    /// When true (multiline only), `#tags` are shown in the primary colour while editing.
    var highlightHashtags: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.Typography.body)
                .fontWeight(.medium)
                .foregroundColor(Theme.Colors.secondaryText)

            if minLines > 1 || (maxLines ?? 1) > 1 {
                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text(placeholder)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.md)
                    }
                    if highlightHashtags {
                        HashtagHighlightingTextEditor(text: $text)
                            .frame(minHeight: minLines > 1 ? CGFloat(minLines) * 24 : 44)
                    } else {
                        TextEditor(text: $text)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(Theme.Spacing.sm)
                            .frame(minHeight: minLines > 1 ? CGFloat(minLines) * 24 : 44)
                    }
                }
                .background(Theme.Colors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 30))
            } else {
                TextField(placeholder, text: $text)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
            }
        }
    }
}
