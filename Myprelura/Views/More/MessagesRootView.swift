import SwiftUI

/// Former “More” tab: staff messaging hub placeholder; **Tools** (console, analytics, orders, banners) live in the wrench menu next to Settings.
struct MessagesRootView: View {
    var wrapsInNavigationStack: Bool = true

    @Environment(AdminSession.self) private var session

    var body: some View {
        Group {
            if wrapsInNavigationStack {
                NavigationStack { root }
            } else {
                root
            }
        }
    }

    private var root: some View {
        List {
            Section {
                ContentUnavailableView(
                    "Messages",
                    systemImage: "message",
                    description: Text("Use this tab for staff inbox and broadcast tools when GraphQL inbox endpoints are wired. Today, open **Reports** for case threads and linked conversation history.")
                )
            }
            Section {
                HStack {
                    Text("Signed in as")
                    Spacer()
                    Text(session.username ?? "—")
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
            }
        }
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }
}
