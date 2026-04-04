import SwiftUI
import UIKit

/// Merged in the scroll view so long-press reaction UI can place the tray above the bubble (global coordinates).
struct ChatBubbleFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

/// Default quick reactions: first row in long-press tray (+ ➕ for full picker).
enum WhatsAppQuickReactions {
    static let primary: [String] = [
        "👍", "❤️", "😂", "😮", "😢", "🙏",
        "🔥", "🎉", "👏", "😍", "🤔", "💯",
    ]

    /// Shown at top of full picker when search is empty (favourites before catalog).
    static let extended: [String] = [
        "😀", "😃", "😄", "😁", "😆", "🥹", "😅", "🤣", "🥲", "☺️",
        "😊", "😍", "🤩", "😘", "🥰", "😎", "🤔", "😴", "🤯", "😭",
        "👏", "👌", "✌️", "🤝", "💪", "🔥", "✨", "💯", "🎉", "❤️‍🔥",
        "💔", "🙌", "👀", "🤷", "🤦", "💩", "🎊", "⭐", "🏆", "🫶"
    ]
}

/// Full-screen dim + reaction capsule above the bubble (reactions only — no message delete).
struct WhatsAppStyleReactionOverlay: View {
    let bubbleFrame: CGRect
    /// Ordered quick reactions (frequently used first; see `ChatReactionEmojiUsageStore`).
    let quickEmojis: [String]
    let onPickEmoji: (String) -> Void
    let onDismiss: () -> Void
    @Binding var showMoreEmojis: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            let safeLead = geo.safeAreaInsets.leading
            let safeTrail = geo.safeAreaInsets.trailing
            /// Keep tray inside safe horizontal bounds (fixed 340pt was wider than narrow phones → clipped edges).
            let maxTrayWidth = max(160, w - safeLead - safeTrail - 16)
            let hasFrame = bubbleFrame.width > 1 && bubbleFrame.height > 1
            let half = maxTrayWidth / 2
            let barX = hasFrame
                ? min(max(bubbleFrame.midX, half + 8 + safeLead), w - half - 8 - safeTrail)
                : (w / 2)
            let barY = hasFrame
                ? max(bubbleFrame.minY - 44, safeTop + 72)
                : safeTop + 100

            ZStack(alignment: .topLeading) {
                Color.black.opacity(0.38)
                    .ignoresSafeArea()
                    .onTapGesture { onDismiss() }

                reactionCapsule(maxWidth: maxTrayWidth, emojis: quickEmojis)
                    .frame(maxWidth: maxTrayWidth)
                    .position(x: barX, y: barY)
            }
        }
    }

    private func reactionCapsule(maxWidth: CGFloat, emojis: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(emojis, id: \.self) { emoji in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onPickEmoji(emoji)
                        onDismiss()
                    } label: {
                        Text(emoji)
                            .font(.system(size: 28))
                            .frame(width: 36, height: 40)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showMoreEmojis = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary, .tertiary)
                        .frame(width: 36, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("More reactions"))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
        .contentMargins(.horizontal, 12, for: .scrollContent)
        .frame(maxWidth: maxWidth)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 14, y: 5)
    }
}

struct ExtendedEmojiReactionSheet: View {
    let onPick: (String) -> Void
    let onDismiss: () -> Void

    @State private var searchText = ""

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 44), spacing: 8)]
    }

    /// Favourites first, then full Unicode-backed catalog (deduped).
    private var orderedPickerEmojis: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in WhatsAppQuickReactions.primary + WhatsAppQuickReactions.extended where seen.insert(e).inserted {
            out.append(e)
        }
        for e in EmojiReactionCatalog.allEmojisForPicker where seen.insert(e).inserted {
            out.append(e)
        }
        return out
    }

    private var filteredEmojis: [String] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return orderedPickerEmojis }
        return orderedPickerEmojis.filter { EmojiReactionCatalog.emojiMatchesSearch($0, query: q) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.Colors.secondaryText)
                    TextField(L10n.string("Search emojis"), text: $searchText)
                        .textFieldStyle(.plain)
                        .foregroundColor(Theme.Colors.primaryText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 10)
                .background(Theme.Colors.secondaryBackground.opacity(0.65))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.Colors.glassBorder, lineWidth: 1)
                )
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.xs)

                ScrollView {
                    if filteredEmojis.isEmpty {
                        Text(L10n.string("No matching emojis"))
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.top, Theme.Spacing.xl)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(filteredEmojis, id: \.self) { emoji in
                                Button {
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    onPick(emoji)
                                    onDismiss()
                                } label: {
                                    Text(emoji)
                                        .font(.system(size: 32))
                                        .frame(minWidth: 44, minHeight: 44)
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.bottom, Theme.Spacing.lg)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color.clear)
            .navigationTitle(L10n.string("Reactions"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.regularMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Done")) { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
