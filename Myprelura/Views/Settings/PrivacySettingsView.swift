import SwiftUI

/// Privacy setting screen (Flutter PrivacySettingRoute).
struct PrivacySettingsView: View {
    var body: some View {
        List {
            NavigationLink(destination: DeleteAccountView()) {
                Label("Delete Account", systemImage: "trash")
                    .foregroundColor(Theme.Colors.primaryText)
            }
            NavigationLink(destination: PauseAccountView()) {
                Label("Pause Account", systemImage: "pause.circle")
                    .foregroundColor(Theme.Colors.primaryText)
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle(L10n.string("Privacy"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

#Preview {
    NavigationStack {
        PrivacySettingsView()
    }
}
