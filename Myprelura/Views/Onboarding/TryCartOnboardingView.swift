import SwiftUI

/// Try Cart intro: three beats inside a **card** (host adds scrim via `TryCartOnboardingPopupOverlay`).
struct TryCartOnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0
    @State private var breathe = false
    @State private var contentAppeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct TryCartPage: Identifiable {
        let id = UUID()
        let titleKey: String
        let bodyKey: String
        let heroAsset: String
        let accent: Color
        let halo: Color
    }

    /// Fixed height for each pager page so copy length varies but layout (text → gap → dots) stays consistent.
    private let tabPageHeight: CGFloat = 408

    private var pages: [TryCartPage] {
        [
            TryCartPage(
                titleKey: "One bag, many sellers",
                bodyKey: "Try Cart lets you add pieces from different shops into a single bag. Keep browsing—your picks stay with you everywhere on Prelura.",
                heroAsset: "TryCartOnboardBag",
                accent: Theme.primaryColor,
                halo: Color(hex: "E8B4FF")
            ),
            TryCartPage(
                titleKey: "Save time on every haul",
                bodyKey: "No more jumping seller by seller. Search, tap the bag, and build your haul in one flow—with a running total so you always know where you stand.",
                heroAsset: "TryCartOnboardBolt",
                accent: Color(hex: "C77DFF"),
                halo: Color(hex: "7C5CFF")
            ),
            TryCartPage(
                titleKey: "Shop smarter, checkout clearer",
                bodyKey: "Use Try Cart from Shop All and favourites. Mix brands freely, review your bag anytime, then check out when you are ready—on your terms.",
                heroAsset: "TryCartOnboardSparkle",
                accent: Color(hex: "FF6B9D"),
                halo: Theme.primaryColor
            )
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.sm)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, p in
                    pageContent(p)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: tabPageHeight)
            .onChange(of: page) { _, _ in
                HapticManager.selection()
                if !reduceMotion {
                    contentAppeared = false
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                        contentAppeared = true
                    }
                }
            }

            bottomChrome
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.bottom, Theme.Spacing.md)
        }
        .background { cardBackground }
        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .preferredColorScheme(.dark)
        .onAppear {
            if !reduceMotion {
                withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) {
                    breathe = true
                }
            } else {
                breathe = true
            }
            contentAppeared = true
        }
    }

    private var cardBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: "07040C"),
                    Color(hex: "12081C"),
                    Color(hex: "0A0610")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Theme.primaryColor.opacity(breathe ? 0.32 : 0.18),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 200
            )

            RadialGradient(
                colors: [
                    Color(hex: "4B1D6E").opacity(breathe ? 0.28 : 0.16),
                    Color.clear
                ],
                center: .bottomLeading,
                startRadius: 8,
                endRadius: 180
            )

            Rectangle()
                .fill(Color.white.opacity(0.025))
                .blendMode(.overlay)
        }
    }

    private var topBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Prelura")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.42))
                Text(L10n.string("Try Cart"))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer(minLength: 8)
            Text("\(page + 1) / \(pages.count)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.white.opacity(0.08)))
            Spacer(minLength: 8)
            Button {
                HapticManager.tap()
                onComplete()
            } label: {
                Text(L10n.string("Skip"))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.1))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                            )
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.string("Skip"))
        }
    }

    @ViewBuilder
    private func pageContent(_ p: TryCartPage) -> some View {
        let scale: CGFloat = contentAppeared ? 1 : (reduceMotion ? 1 : 0.96)
        let opacity: Double = contentAppeared ? 1 : (reduceMotion ? 1 : 0)

        VStack(spacing: 0) {
            Spacer(minLength: 4)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [p.halo.opacity(0.5), p.accent.opacity(0.12), .clear],
                            center: .center,
                            startRadius: 8,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)
                    .blur(radius: 22)

                ZStack {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.5), .white.opacity(0.08)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.2
                        )
                        .frame(width: 112, height: 112)

                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 106, height: 106)
                        .shadow(color: p.accent.opacity(0.32), radius: 20, y: 10)

                    Image(p.heroAsset)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
            .padding(.bottom, Theme.Spacing.md)

            Text(L10n.string(p.titleKey))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .padding(.horizontal, Theme.Spacing.sm)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)

            Text(L10n.string(p.bodyKey))
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.white.opacity(0.82))
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.top, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.lg)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: Theme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, minHeight: tabPageHeight, maxHeight: tabPageHeight, alignment: .top)
        .padding(.horizontal, Theme.Spacing.sm)
        .scaleEffect(scale)
        .opacity(opacity)
    }

    private var bottomChrome: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { i in
                    Capsule()
                        .fill(
                            i == page
                                ? LinearGradient(
                                    colors: [.white, Color.white.opacity(0.85)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                : LinearGradient(
                                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.28)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                        )
                        .frame(width: i == page ? 26 : 6, height: 6)
                        .animation(.spring(response: 0.4, dampingFraction: 0.72), value: page)
                }
            }
            .padding(.top, Theme.Spacing.md)

            // No `PrimaryButtonBar` here — it uses `Theme.Colors.background` (flat black) which clashes with the card gradient.
            Group {
                if page < pages.count - 1 {
                    PrimaryGlassButton(L10n.string("Next")) {
                        withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                            page += 1
                        }
                    }
                } else {
                    PrimaryGlassButton(L10n.string("Start shopping")) {
                        HapticManager.success()
                        onComplete()
                    }
                }
            }
            .padding(.top, Theme.Spacing.xs)
        }
    }
}

// MARK: - Popup shell (scrim + animation; avoids fullScreenCover / status-bar overlap)

/// Dimmed backdrop + centered card. Use as an overlay on the host screen.
struct TryCartOnboardingPopupOverlay: View {
    var onComplete: () -> Void
    @State private var presented = false

    var body: some View {
        GeometryReader { geo in
            let horizontalPad: CGFloat = 18
            let maxCardW = min(geo.size.width - horizontalPad * 2, 420)
            let maxCardH = min(geo.size.height - geo.safeAreaInsets.top - geo.safeAreaInsets.bottom - 24, 720)

            ZStack {
                Color.black
                    .opacity(presented ? 0.5 : 0)
                    .ignoresSafeArea()
                    .animation(.easeOut(duration: 0.2), value: presented)

                TryCartOnboardingView(onComplete: onComplete)
                    .frame(width: maxCardW)
                    .frame(maxHeight: maxCardH)
                    .scaleEffect(presented ? 1 : 0.94, anchor: .center)
                    .opacity(presented ? 1 : 0)
                    .shadow(color: .black.opacity(0.5), radius: 32, y: 18)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear {
            withAnimation(.spring(response: 0.44, dampingFraction: 0.82)) {
                presented = true
            }
        }
    }
}

#Preview("Card") {
    ZStack {
        Color.gray.opacity(0.3)
        TryCartOnboardingView(onComplete: {})
            .padding()
    }
}

#Preview("Popup") {
    TryCartOnboardingPopupOverlay(onComplete: {})
}
