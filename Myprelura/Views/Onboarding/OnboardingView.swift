import SwiftUI

/// First-launch onboarding flow (Flutter OnboardingRoute). Simple welcome screens; can be extended with more pages.
struct OnboardingView: View {
    var onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: Theme.Spacing.xl) {
                TabView(selection: $page) {
                    onboardingPage(
                        title: "Welcome to Prelura",
                        bodyText: "Buy and sell preloved fashion. Sustainable choices, one tap away.",
                        imageName: "leaf.fill"
                    )
                    .tag(0)
                    onboardingPage(
                        title: "Shop & Sell",
                        bodyText: "Discover unique items from the community or list your own.",
                        imageName: "bag.fill"
                    )
                    .tag(1)
                    onboardingPage(
                        title: "Stay in the Loop",
                        bodyText: "Get notified when items you love go on sale or when someone messages you.",
                        imageName: "bell.badge.fill"
                    )
                    .tag(2)
                    onboardingPage(
                        title: "You're All Set",
                        bodyText: "Your feed is ready. Start exploring and make your first sustainable find.",
                        imageName: "sparkles"
                    )
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(page == i ? Theme.primaryColor : Theme.Colors.secondaryText.opacity(0.4))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)

            PrimaryButtonBar {
                PrimaryGlassButton("Get started", action: onComplete)
            }
        }
    }

    private func onboardingPage(title: String, bodyText: String, imageName: String) -> some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: imageName)
                .font(.system(size: 72))
                .foregroundColor(Theme.primaryColor)
            Text(title)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
                .multilineTextAlignment(.center)
            Text(bodyText)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal)
    }
}

#Preview {
    OnboardingView(onComplete: {})
}
