import SwiftUI

/// Staff Messages tab: empty until inbox APIs are wired. No placeholder copy or account strip — same pattern as an empty shopper inbox.
struct MessagesRootView: View {
    var wrapsInNavigationStack: Bool = true

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
        ContentUnavailableView("No messages", systemImage: "message")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.Colors.background)
            .navigationTitle("Messages")
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
    }
}
