import SwiftUI

/// Invite a friend — redesigned: one intro, three equal-weight actions in a single list style.
struct InviteFriendView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                // Intro
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Bring friends to Prelura")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.primaryText)
                    Text("Share your profile or invite from your contacts.")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)

                // Actions: same style, same height
                VStack(spacing: Theme.Spacing.sm) {
                    NavigationLink(destination: ListOfContactsView()) {
                        inviteRow(
                            icon: "person.crop.circle.badge.plus",
                            title: "Invite a contact",
                            subtitle: "Choose from your contacts"
                        )
                    }
                    .buttonStyle(PlainTappableButtonStyle())

                    Button(action: { shareProfileLink() }) {
                        inviteRow(
                            icon: "link",
                            title: "Share profile link",
                            subtitle: "Copy or share your link"
                        )
                    }
                    .buttonStyle(PlainTappableButtonStyle())

                    Button(action: {}) {
                        inviteRow(
                            icon: "person.2.fill",
                            title: "Invite via Facebook",
                            subtitle: "Connect with Facebook friends",
                            iconColor: Color(red: 0.23, green: 0.35, blue: 0.6)
                        )
                    }
                    .buttonStyle(PlainTappableButtonStyle())
                }
                .padding(.horizontal, Theme.Spacing.md)
            }
            .padding(.vertical, Theme.Spacing.lg)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Invite a friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    private func inviteRow(
        icon: String,
        title: String,
        subtitle: String,
        iconColor: Color = Theme.primaryColor
    ) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(iconColor)
                .frame(width: 32, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.primaryText)
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.Colors.tertiaryText)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.secondaryBackground)
        .cornerRadius(Theme.Glass.cornerRadius)
    }

    private func shareProfileLink() {
        // TODO: copy or share profile URL
    }
}
