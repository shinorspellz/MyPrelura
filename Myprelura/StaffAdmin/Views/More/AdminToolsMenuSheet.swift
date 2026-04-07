import SwiftUI

/// Optional modal wrapper around `StaffToolsListView` (prefer `NavigationLink` from Home for iPad).
struct AdminToolsMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            StaffToolsListView()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
        }
    }
}
