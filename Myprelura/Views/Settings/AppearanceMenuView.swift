import SwiftUI

/// Appearance: theme (System / Light / Dark). Language is in Settings > Language.
struct AppearanceMenuView: View {
    @AppStorage(kAppearanceMode) private var appearanceMode: String = "system"

    private var options: [(id: String, title: String)] {
        [
            ("system", L10n.string("Use System Settings")),
            ("light", L10n.string("Light")),
            ("dark", L10n.string("Dark"))
        ]
    }

    var body: some View {
        List {
            Section {
                ForEach(options, id: \.id) { option in
                    Button(action: { appearanceMode = option.id }) {
                        HStack {
                            Text(option.title)
                                .foregroundColor(Theme.Colors.primaryText)
                            Spacer()
                            if appearanceMode == option.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Theme.primaryColor)
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.string("Theme"))
            } footer: {
                Text(L10n.string("Light and Dark apply to all screens, components, and elements. System follows your device setting."))
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Appearance"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
