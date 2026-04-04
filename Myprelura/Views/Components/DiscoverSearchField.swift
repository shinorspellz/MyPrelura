import SwiftUI

/// Reusable discover-style search field with 30pt corner radius.
/// When animatedPlaceholders is set, cycles through them with a fade; otherwise uses static placeholder.
struct DiscoverSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    var placeholder: String = "Search members"
    /// When non-empty, placeholder cycles through these with animation (e.g. Discover tab member search).
    var animatedPlaceholders: [String]? = nil
    var onSubmit: (() -> Void)? = nil
    var onChange: ((String) -> Void)? = nil
    var showClearButton: Bool = false
    var onClear: (() -> Void)? = nil
    var outerPadding: Bool = true
    var topPadding: CGFloat? = nil
    var fieldBackground: Color? = nil
    /// When true, keeps the field at a fixed single-line height; text scrolls horizontally instead of wrapping or growing.
    var singleLineFixedHeight: Bool = false

    @State private var placeholderIndex: Int = 0
    @State private var placeholderOpacity: Double = 1
    @State private var cycleTimer: Timer?
    @State private var placeholders: [String] = []

    private let cornerRadius: CGFloat = 30
    private static let singleLineHeight: CGFloat = 44

    private var useAnimatedPlaceholders: Bool {
        guard let list = animatedPlaceholders, !list.isEmpty else { return false }
        return true
    }

    private var currentPlaceholderText: String {
        if useAnimatedPlaceholders, !placeholders.isEmpty {
            return placeholders[placeholderIndex % placeholders.count]
        }
        return placeholder
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.Colors.secondaryText)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(currentPlaceholderText)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .opacity(placeholderOpacity)
                        .lineLimit(singleLineFixedHeight ? 1 : nil)
                        .truncationMode(singleLineFixedHeight ? .tail : .tail)
                }
                TextField("", text: $text)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .focused($isFocused)
                    .lineLimit(singleLineFixedHeight ? 1 : nil)
                    .onSubmit { onSubmit?() }
                    .onChange(of: text) { _, newValue in onChange?(newValue) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            if showClearButton && !text.isEmpty {
                Button(action: {
                    text = ""
                    onClear?()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
        }
        .onAppear {
            if useAnimatedPlaceholders {
                placeholders = (animatedPlaceholders ?? []).shuffled()
                startPlaceholderCycle()
            }
        }
        .onDisappear {
            cycleTimer?.invalidate()
            cycleTimer = nil
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, singleLineFixedHeight ? 0 : Theme.Spacing.md)
        .frame(height: singleLineFixedHeight ? Self.singleLineHeight : nil)
        .background(fieldBackground ?? Theme.Colors.secondaryBackground)
        .cornerRadius(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isFocused ? Theme.primaryColor : Color.clear, lineWidth: 2)
        )
        .modifier(DiscoverSearchFieldOuterPadding(outerPadding: outerPadding, topPadding: topPadding))
    }

    private func startPlaceholderCycle() {
        cycleTimer?.invalidate()
        guard placeholders.count > 1 else { return }
        cycleTimer = Timer.scheduledTimer(withTimeInterval: 3.2, repeats: true) { _ in
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.25)) {
                    placeholderOpacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    placeholderIndex = (placeholderIndex + 1) % placeholders.count
                    withAnimation(.easeIn(duration: 0.25)) {
                        placeholderOpacity = 1
                    }
                }
            }
        }
        RunLoop.main.add(cycleTimer!, forMode: .common)
    }
}

private struct DiscoverSearchFieldOuterPadding: ViewModifier {
    let outerPadding: Bool
    let topPadding: CGFloat?
    func body(content: Content) -> some View {
        let top = topPadding ?? Theme.Spacing.sm
        if outerPadding {
            content
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, top)
                .padding(.bottom, Theme.Spacing.xs)
        } else {
            content
                .padding(.top, top)
                .padding(.bottom, Theme.Spacing.xs)
        }
    }
}

#Preview {
    VStack {
        DiscoverSearchField(text: .constant(""))
        DiscoverSearchField(text: .constant("test"), showClearButton: true)
    }
    .padding()
}
