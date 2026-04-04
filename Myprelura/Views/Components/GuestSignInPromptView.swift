import SwiftUI

/// Same guest sign-in prompt shown on Profile and Messages (Inbox). Use when user is browsing as guest and tries to access gated content (profile, messages, or like).
struct GuestSignInPromptView: View {
    @EnvironmentObject var authService: AuthService

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer(minLength: 60)
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 64))
                .foregroundColor(Theme.Colors.secondaryText)
            Text(L10n.string("You're browsing as guest"))
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.primaryText)
                .multilineTextAlignment(.center)
            Text(L10n.string("Sign in to see your profile, listings and messages."))
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(action: { authService.clearGuestMode() }) {
                Text(L10n.string("Sign in"))
                    .font(Theme.Typography.body)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .background(Theme.primaryColor)
            .cornerRadius(24)
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.sm)
            Spacer(minLength: 60)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.background)
    }
}
