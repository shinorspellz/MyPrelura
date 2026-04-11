import SwiftUI

/// Optional modal wrapper around `StaffToolsListView` (prefer `NavigationLink` from Home for iPad).
struct AdminToolsMenuSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService

    var body: some View {
        NavigationStack {
            StaffToolsListView()
                .environmentObject(authService)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
