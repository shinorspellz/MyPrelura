import SwiftUI

/// Location text field with dropdown suggestions from a bundled list of cities, towns, and countries only (no street addresses).
/// User can type to filter and tap a suggestion to fill the field. No external API — all data is local.
struct LocationSuggestionField: View {
    let placeholder: String
    @Binding var text: String
    /// When false, suggestions list is hidden (e.g. when focus leaves).
    var isFocused: Bool = true

    @State private var suggestions: [String] = []
    @State private var showSuggestions: Bool = false
    private let service = LocationSuggestionService()
    private let cornerRadius: CGFloat = 30
    private let debounceInterval: Double = 0.15
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField(placeholder, text: $text)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.primaryText)
                .textContentType(.addressCity)
                .autocorrectionDisabled()
                .onChange(of: text) { _, newValue in
                    guard isFocused else {
                        suggestions = []
                        showSuggestions = false
                        return
                    }
                    debounceTask?.cancel()
                    debounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(debounceInterval * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if q.isEmpty {
                            suggestions = []
                            showSuggestions = false
                        } else {
                            let result = await service.suggestionsAsync(for: q)
                            guard !Task.isCancelled else { return }
                            suggestions = result
                            showSuggestions = !suggestions.isEmpty
                        }
                    }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { showSuggestions = false }
                }
                .onTapGesture {
                    if !text.isEmpty {
                        Task { @MainActor in
                            suggestions = await service.suggestionsAsync(for: text)
                            showSuggestions = !suggestions.isEmpty
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(cornerRadius)

            if showSuggestions && !suggestions.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button {
                            text = suggestion
                            showSuggestions = false
                            suggestions = []
                        } label: {
                            Text(suggestion)
                                .font(Theme.Typography.body)
                                .foregroundColor(Theme.Colors.primaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.sm)
                        }
                        .buttonStyle(PlainTappableButtonStyle())
                        if suggestion != suggestions.last {
                            Divider()
                                .background(Theme.Colors.glassBorder.opacity(0.5))
                                .padding(.leading, Theme.Spacing.md)
                        }
                    }
                }
                .background(Theme.Colors.secondaryBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Theme.Colors.glassBorder.opacity(0.5), lineWidth: 1)
                )
                .padding(.top, 4)
            }
        }
    }
}
