import SwiftUI

/// Full-screen Menu page. Pushed from Profile. Refreshes multibuy/vacation state from API on appear and when profile updates.
struct MenuView: View {
    @EnvironmentObject var authService: AuthService

    var listingCount: Int = 0
    var isMultiBuyEnabled: Bool = false
    var isVacationMode: Bool = false
    var username: String? = nil

    @State private var displayedMultiBuy: Bool = false
    @State private var displayedVacation: Bool = false
    @State private var showLogoutConfirm = false

    private let userService = UserService()

    var body: some View {
        List {
            NavigationLink(destination: LookbookView()) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.body)
                        .foregroundStyle(Theme.Colors.secondaryText)
                    Text("Lookbook")
                        .foregroundColor(Theme.Colors.primaryText)
                    Spacer()
                    Text("Beta")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(Theme.primaryColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Theme.primaryColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
#if DEBUG
            NavigationLink(destination: DebugMenuView()) {
                menuRow(L10n.string("Debug"), icon: "ladybug")
            }
#endif
            NavigationLink(destination: ShopValueView(listingCount: listingCount)) {
                menuRow(L10n.string("Seller dashboard"), icon: "chart.bar")
            }
            NavigationLink(destination: MyOrdersView()) {
                menuRow(L10n.string("Orders"), icon: "bag")
            }
            NavigationLink(destination: MyFavouritesView()) {
                menuRow(L10n.string("Favourites"), icon: "heart")
            }
            NavigationLink(destination: MultiBuyDiscountView()) {
                HStack {
                    menuRow(L10n.string("Multi-buy discounts"), icon: "tag")
                    Spacer()
                    Text(displayedMultiBuy ? L10n.string("On") : L10n.string("Off"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            NavigationLink(destination: VacationModeView(initialIsOn: displayedVacation)) {
                HStack {
                    menuRow(L10n.string("Vacation Mode"), icon: "umbrella")
                    Spacer()
                    Text(displayedVacation ? L10n.string("On") : L10n.string("Off"))
                        .font(.system(size: 14))
                        .foregroundColor(Theme.Colors.secondaryText)
                }
            }
            NavigationLink(destination: InviteFriendView()) {
                menuRow(L10n.string("Invite Friend"), icon: "person.badge.plus")
            }
            NavigationLink(destination: HelpCentreView()) {
                menuRow(L10n.string("Help Centre"), icon: "questionmark.circle")
            }
            NavigationLink(destination: AboutPreluraMenuView()) {
                menuRow(L10n.string("About Prelura"), icon: "info.circle")
            }
            Button(role: .destructive, action: {
                showLogoutConfirm = true
            }) {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.body)
                        .foregroundColor(.red)
                    Text(L10n.string("Logout"))
                        .foregroundColor(.red)
                    Spacer()
                }
            }
            .buttonStyle(HapticTapButtonStyle(haptic: { HapticManager.destructive() }))
            Section {
                EmptyView()
            } footer: {
                Text(L10n.string("© Voltis Labs 2026"))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Theme.Spacing.sm)
                    .padding(.bottom, Theme.Spacing.xs)
            }
        }
        .onAppear {
            displayedMultiBuy = isMultiBuyEnabled
            displayedVacation = isVacationMode
            Task { await refreshUserState() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .preluraUserProfileDidUpdate)) { _ in
            Task { await refreshUserState() }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Menu"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SettingsMenuView()) {
                    Image(systemName: "gearshape")
                        .foregroundColor(Theme.Colors.primaryText)
                }
                .buttonStyle(HapticTapButtonStyle())
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .alert(L10n.string("Logout"), isPresented: $showLogoutConfirm) {
            Button(L10n.string("Cancel"), role: .cancel) { HapticManager.tap() }
            Button(L10n.string("Logout"), role: .destructive) {
                HapticManager.destructive()
                Task {
                    await authService.logout()
                }
            }
        } message: {
            Text(L10n.string("Are you sure you want to logout?"))
        }
    }
    
    private func menuRow(_ title: String, icon: String) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.Colors.secondaryText)
            Text(title)
        }
    }

    private func refreshUserState() async {
        userService.updateAuthToken(authService.authToken)
        do {
            let user = try await userService.getUser()
            await MainActor.run {
                displayedMultiBuy = user.isMultibuyEnabled
                displayedVacation = user.isVacationMode
            }
        } catch {
            // Keep displayed state from params / previous fetch
        }
    }
}
