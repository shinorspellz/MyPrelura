import SwiftUI

/// Debug menu screen – submenu for debug tools and component showcase.
struct DebugMenuView: View {
    var body: some View {
        List {
            Section {
                Text("Build: \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.secondaryText)
            } header: {
                Text("Info")
            }
            Section {
                NavigationLink(destination: PushDiagnosticsView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "bell.badge")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Push diagnostics")
                    }
                }
                NavigationLink(destination: MessageChatPushTraceDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "bubble.left.and.text.bubble.right")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Message push trace")
                    }
                }
                NavigationLink(destination: ChatThreadLiveUpdateDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Chat live update trace")
                    }
                }
                NavigationLink(destination: WebSocketConnectionDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "network")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("WebSocket test")
                    }
                }
                #if DEBUG
                NavigationLink(destination: MessageDeliveryDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "paperplane")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Message delivery test")
                    }
                }
                #endif
                NavigationLink(destination: NotificationTypeMatrixDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "list.bullet.rectangle.portrait")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Notification matrix")
                    }
                }
                NavigationLink(destination: OrderChatMockDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Order")
                    }
                }
                NavigationLink(destination: ProfileCardsComponentsView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Profile cards, and components")
                    }
                }
                NavigationLink(destination: GlassMaterialsView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "drop.fill")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Glass materials")
                    }
                }
                NavigationLink(destination: GlassEffectTransitionView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Glass effect transition")
                    }
                }
                NavigationLink(destination: AnimatedScreenDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Animated screen")
                    }
                }
                NavigationLink(destination: BlackScreensMenuView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "square.fill")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Black screens")
                    }
                }
                NavigationLink(destination: DashboardView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "chart.bar.doc.horizontal")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Dashboard")
                    }
                }
                NavigationLink(destination: OrderScreenDebugView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "doc.text")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text("Order screen")
                    }
                }
                NavigationLink(destination: ShopToolsView()) {
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.body)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        Text(L10n.string("Shop tools"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .background(Theme.Colors.background)
        .navigationTitle("Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}
