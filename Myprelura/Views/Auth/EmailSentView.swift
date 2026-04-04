import SwiftUI

/// Confirmation that an email was sent (e.g. after forgot password or signup verification).
struct EmailSentView: View {
    let email: String
    var title: String = "Email sent"
    var message: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 64))
                .foregroundColor(Theme.primaryColor)
            Text(title)
                .font(Theme.Typography.title2)
                .foregroundColor(Theme.Colors.primaryText)
            Text(message ?? "An email was sent to \(email) for verification.")
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Back to login") {
                dismiss()
            }
            .font(Theme.Typography.headline)
            .foregroundColor(Theme.primaryColor)
            .padding(.top, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.background)
    }
}

#Preview {
    EmailSentView(email: "user@example.com")
}
