import SwiftUI

/// Sheet listing staff utilities (moved out of the Messages tab toolbar pattern).
struct AdminToolsMenuSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Operations") {
                    NavigationLink {
                        ConsoleView()
                    } label: {
                        Label("Console", systemImage: "slider.horizontal.3")
                    }
                    NavigationLink {
                        AnalyticsDetailView()
                    } label: {
                        Label("Analytics", systemImage: "chart.xyaxis.line")
                    }
                    NavigationLink {
                        TransactionsView(wrapsInNavigationStack: false)
                    } label: {
                        Label("Orders", systemImage: "sterlingsign.circle")
                    }
                    NavigationLink {
                        BannersAnnouncementsView()
                    } label: {
                        Label("Home banners", systemImage: "photo.on.rectangle.angled")
                    }
                }
            }
            .navigationTitle("Tools")
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
