import SwiftUI

struct SettingsHubView: View {
    @Environment(AdminSession.self) private var session
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        List {
            Section("Preferences") {
                NavigationLink {
                    AppearanceSettingsView()
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                NavigationLink {
                    HapticsSettingsView()
                } label: {
                    Label("Haptics", systemImage: "hand.tap")
                }
                NavigationLink {
                    NotificationsSettingsPlaceholderView()
                } label: {
                    Label("Notifications", systemImage: "bell.badge")
                }
            }

            Section("Network") {
                NavigationLink {
                    APIInfoSettingsView()
                } label: {
                    Label("API endpoint", systemImage: "network")
                }
            }

            Section("About") {
                NavigationLink {
                    AboutSettingsView()
                } label: {
                    Label("About Myprelura", systemImage: "info.circle")
                }
                NavigationLink {
                    PrivacyPlaceholderView()
                } label: {
                    Label("Privacy & data", systemImage: "lock.shield")
                }
            }

            Section {
                Button(role: .destructive) {
                    session.signOut()
                    authService.reloadTokensFromStorage()
                } label: {
                    Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .navigationTitle("Admin settings")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }
}

/// Same structure as consumer `AppearanceMenuView` / `kAppearanceMode` (`appearance_mode`).
struct AppearanceSettingsView: View {
    @AppStorage(Constants.appearanceModeStorageKey) private var appearanceMode = "system"

    private var options: [(id: String, title: String)] {
        [
            ("system", "Use System Settings"),
            ("light", "Light"),
            ("dark", "Dark"),
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.id) { option in
                    Button {
                        appearanceMode = option.id
                    } label: {
                        HStack {
                            Text(option.title)
                                .foregroundStyle(Theme.Colors.primaryText)
                            Spacer()
                            if appearanceMode == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.primaryColor)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                }
            } header: {
                Text("Theme")
            } footer: {
                Text("Light and Dark apply to all screens, components, and elements. System follows your device setting.")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
    }
}

struct HapticsSettingsView: View {
    @AppStorage("myprelura.settings.haptics") private var hapticsOn = true

    var body: some View {
        Form {
            Section {
                Toggle("Haptic feedback", isOn: $hapticsOn)
            } footer: {
                Text("When off, selection taps in the admin shell stay silent.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Haptics")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
    }
}

struct NotificationsSettingsPlaceholderView: View {
    var body: some View {
        ScrollView {
            Text("Push routing, quiet hours, and report digests need backend notification-preference fields. This page is wired for when those APIs exist.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Notifications")
        .adminNavigationChrome()
    }
}

struct APIInfoSettingsView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("GraphQL", value: Constants.graphQLBaseURL)
            } footer: {
                Text("Endpoint is shared with the consumer app. Changes require an app update.")
            }
            Section {
                LabeledContent("Public web", value: Constants.publicWebBaseURL)
            }
        }
        .navigationTitle("API endpoint")
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }
}

struct AboutSettingsView: View {
    var body: some View {
        List {
            Section {
                LabeledContent("App", value: "Myprelura")
                LabeledContent("Bundle", value: Bundle.main.bundleIdentifier ?? "—")
            }
        }
        .navigationTitle("About")
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }
}

struct PrivacyPlaceholderView: View {
    var body: some View {
        ScrollView {
            Text("Data handling follows the same policies as the consumer Prelura app. Export, deletion, and audit tooling will link here when staff-specific flows are exposed.")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.Colors.secondaryText)
                .padding()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Privacy & data")
        .adminNavigationChrome()
    }
}
