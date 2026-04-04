import SwiftUI

/// Gender-conscious product search placeholders (randomised when used).
private let feedSearchPlaceholders: [String] = [
    "Women's vintage dress",
    "Men's casual jacket",
    "Kids trainers",
    "Unisex hoodie",
    "Summer sandals",
    "Maternity wear",
    "Neutral blazer",
    "Brands or colours",
    "Women's blouse",
    "Men's jeans",
    "Baby & toddler",
    "Formal dress",
    "Streetwear",
    "Sustainable fashion",
    "Plus size",
    "Petite range",
]

/// Feed search field with optional AI icon that opens the dedicated AI chat.
/// Placeholder cycles through gender-conscious suggestions with a fade animation.
/// Submit parses query with AISearchService and calls onSubmit(ParsedSearch).
struct FeedSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool
    @State private var aiButtonScale: CGFloat = 1.0
    @State private var placeholderIndex: Int = 0
    @State private var placeholderOpacity: Double = 1
    @State private var cycleTimer: Timer?
    @State private var placeholders: [String] = []

    var onSubmit: ((ParsedSearch) -> Void)?
    var onAITap: (() -> Void)?
    var topPadding: CGFloat? = nil

    private let cornerRadius: CGFloat = 30
    private let aiSearch = AISearchService()

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.Colors.secondaryText)

            ZStack(alignment: .leading) {
                if text.isEmpty {
                    Text(currentPlaceholder)
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                        .opacity(placeholderOpacity)
                }
                TextField("", text: $text)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.primaryText)
                    .focused($isFocused)
                    .onSubmit {
                        let parsed = aiSearch.parse(query: text.trimmingCharacters(in: .whitespacesAndNewlines))
                        onSubmit?(parsed)
                    }
            }

            if let onAITap = onAITap {
                Button(action: onAITap) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Theme.primaryColor)
                        .scaleEffect(aiButtonScale)
                }
                .buttonStyle(HapticTapButtonStyle())
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                aiButtonScale = 1.2
            }
            startPlaceholderCycle()
        }
        .onDisappear {
            cycleTimer?.invalidate()
            cycleTimer = nil
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(isFocused ? Theme.primaryColor : Color.clear, lineWidth: 2)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, topPadding ?? Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private var currentPlaceholder: String {
        guard !placeholders.isEmpty else { return "Search items, brands or colours" }
        return placeholders[placeholderIndex % placeholders.count]
    }

    private func startPlaceholderCycle() {
        cycleTimer?.invalidate()
        if placeholders.isEmpty {
            placeholders = feedSearchPlaceholders.shuffled()
        }
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
