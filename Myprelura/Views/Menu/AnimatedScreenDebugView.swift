import SwiftUI

/// Debug-only sample inspired by premium dark “invest” dashboards: fluid blue glow, glass chips, and soft motion. Not affiliated with any bank.
struct AnimatedScreenDebugView: View {
    @State private var cardAppeared = false

    var body: some View {
        ZStack(alignment: .bottom) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { context in
                FluidBankingBackground(t: context.date.timeIntervalSinceReferenceDate)
            }
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    topChrome
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                    balanceBlock
                        .padding(.top, 28)

                    quickActionsRow
                        .padding(.top, 28)
                        .padding(.horizontal, 8)

                    VStack(spacing: 12) {
                        sampleCard(
                            icon: "cube.transparent.fill",
                            iconColors: [Color(red: 0.95, green: 0.75, blue: 0.35), Color(red: 0.7, green: 0.45, blue: 0.15)],
                            title: "Sample commodities",
                            subtitle: nil,
                            trailing: "£0",
                            showChevron: false
                        )
                        sampleCard(
                            icon: "chart.bar.fill",
                            iconColors: [Color.blue.opacity(0.9), Color.cyan.opacity(0.7)],
                            title: "General portfolio",
                            subtitle: "Build a mix of listings and saved searches.",
                            trailing: nil,
                            showChevron: true
                        )
                        sampleCard(
                            icon: "percent",
                            iconColors: [Color.purple.opacity(0.85), Color.blue.opacity(0.6)],
                            title: "Tax‑wrapper sample",
                            subtitle: "Illustration only — not financial advice.",
                            trailing: nil,
                            showChevron: true
                        )
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 120)
                    .opacity(cardAppeared ? 1 : 0)
                    .offset(y: cardAppeared ? 0 : 24)
                    .animation(.spring(response: 0.55, dampingFraction: 0.82).delay(0.05), value: cardAppeared)
                }
            }

            floatingBottomNav
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .navigationTitle("Animated screen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .preferredColorScheme(.dark)
        .onAppear { cardAppeared = true }
    }

    // MARK: - Top chrome

    private var topChrome: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(red: 0.72, green: 0.58, blue: 0.42))
                .frame(width: 40, height: 40)
                .overlay(
                    Text("P")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                )

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
                Text("Search")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))

            HStack(spacing: 8) {
                glassIconButton("chart.bar.xaxis")
                glassIconButton("globe")
            }
        }
    }

    private func glassIconButton(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 40, height: 40)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Balance

    private var balanceBlock: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("£0")
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Image(systemName: "info.circle")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(.white.opacity(0.35))
            }
            Text("£0  ·  0.00%")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Quick actions

    private var quickActionsRow: some View {
        HStack(spacing: 0) {
            quickAction(icon: "arrow.up.right", label: "Trade", dimmed: false)
            quickAction(icon: "plus", label: "Add", dimmed: true)
            quickAction(icon: "arrow.down", label: "Withdraw", dimmed: true)
            quickAction(icon: "ellipsis", label: "More", dimmed: false)
        }
    }

    private func quickAction(icon: String, label: String, dimmed: Bool) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(dimmed ? .white.opacity(0.35) : .white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.08), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.1), lineWidth: 1))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(dimmed ? .white.opacity(0.35) : .white.opacity(0.85))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cards

    private func sampleCard(
        icon: String,
        iconColors: [Color],
        title: String,
        subtitle: String?,
        trailing: String?,
        showChevron: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(colors: iconColors, startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.28))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - Bottom nav (decorative)

    private var floatingBottomNav: some View {
        HStack(spacing: 0) {
            navPillItem(icon: "house.fill", label: "Home", selected: false)
            navPillItem(icon: "chart.bar.fill", label: "Invest", selected: true)
            navPillItem(icon: "arrow.left.arrow.right", label: "Pay", selected: false)
            navPillItem(icon: "bitcoinsign.circle.fill", label: "Crypto", selected: false)
            navPillItem(icon: "sparkles", label: "Rewards", selected: false)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 20, y: 10)
    }

    private func navPillItem(icon: String, label: String, selected: Bool) -> some View {
        VStack(spacing: 4) {
            ZStack {
                if selected {
                    Circle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 40, height: 40)
                }
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selected ? .white : .white.opacity(0.38))
            }
            .frame(height: 40)
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(selected ? .white.opacity(0.9) : .white.opacity(0.35))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Animated fluid background

private struct FluidBankingBackground: View {
    let t: TimeInterval

    var body: some View {
        ZStack {
            Color(red: 0.02, green: 0.02, blue: 0.05)

            glowBlob(
                colors: [Color(red: 0.15, green: 0.35, blue: 0.95).opacity(0.65), Color.clear],
                size: CGSize(width: 420, height: 320),
                rotation: sin(t * 0.35) * 18 + 42,
                offset: CGSize(
                    width: 40 + sin(t * 0.28) * 50,
                    height: -140 + cos(t * 0.22) * 35
                ),
                blur: 55
            )

            glowBlob(
                colors: [Color.cyan.opacity(0.35), Color.blue.opacity(0.15), Color.clear],
                size: CGSize(width: 280, height: 260),
                rotation: cos(t * 0.31) * 22 - 25,
                offset: CGSize(
                    width: -120 + cos(t * 0.26) * 45,
                    height: -60 + sin(t * 0.24) * 40
                ),
                blur: 45
            )

            glowBlob(
                colors: [Color.purple.opacity(0.25), Color.clear],
                size: CGSize(width: 200, height: 200),
                rotation: sin(t * 0.5) * 30,
                offset: CGSize(width: 100, height: 40 + sin(t * 0.4) * 20),
                blur: 35
            )

            LinearGradient(
                colors: [Color.clear, Color.black.opacity(0.92)],
                startPoint: .center,
                endPoint: .bottom
            )
        }
    }

    private func glowBlob(
        colors: [Color],
        size: CGSize,
        rotation: Double,
        offset: CGSize,
        blur: CGFloat
    ) -> some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 10,
                    endRadius: max(size.width, size.height) * 0.55
                )
            )
            .frame(width: size.width, height: size.height)
            .rotationEffect(.degrees(rotation))
            .offset(x: offset.width, y: offset.height)
            .blur(radius: blur)
    }
}

#Preview {
    NavigationStack {
        AnimatedScreenDebugView()
    }
}
