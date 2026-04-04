import SwiftUI

/// Internal ops switchboard: probes live services and allows **local-only** “simulate outage” toggles (never sent to the API).
struct ConsoleView: View {
    @Environment(AdminSession.self) private var session

    @AppStorage("myprelura.console.sim.graphql") private var simulateGraphQLDown = false
    @AppStorage("myprelura.console.sim.analytics") private var simulateAnalyticsDown = false
    @AppStorage("myprelura.console.sim.reports") private var simulateReportsDown = false
    @AppStorage("myprelura.console.sim.publicWeb") private var simulatePublicWebDown = false

    @State private var lines: [ConsoleLine] = []
    @State private var lastProbeAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Private probe runs when you open this screen (and on refresh). Simulated outages only affect this device.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)

                mixerStrip

                if let lastProbeAt {
                    Text("Last probe: \(lastProbeAt.formatted(date: .omitted, time: .standard))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Simulate outage (local)")
                            .font(Theme.Typography.headline)
                        Toggle("GraphQL API", isOn: $simulateGraphQLDown)
                        Toggle("Analytics field", isOn: $simulateAnalyticsDown)
                        Toggle("Reports field", isOn: $simulateReportsDown)
                        Toggle("Public web (prelura.uk)", isOn: $simulatePublicWebDown)
                    }
                }

                ForEach(lines) { line in
                    statusRow(line)
                }
            }
            .padding()
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .refreshable { await runProbes() }
        .task { await runProbes() }
    }

    private var mixerStrip: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(lines) { line in
                VStack(spacing: 6) {
                    Circle()
                        .fill(line.up ? Color.green : Color.red)
                        .frame(width: 28, height: 28)
                        .shadow(color: (line.up ? Color.green : Color.red).opacity(0.45), radius: 6)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.secondaryText.opacity(0.35))
                        .frame(width: 6, height: CGFloat(24 + min(line.latencyMs, 400) / 20))
                    Text(shortTitle(line.name))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.tertiaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(width: 56)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 8)
    }

    private func shortTitle(_ name: String) -> String {
        name.replacingOccurrences(of: " ", with: "\n")
    }

    private func statusRow(_ line: ConsoleLine) -> some View {
        GlassCard {
            HStack {
                Circle()
                    .fill(line.up ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(line.name)
                        .font(Theme.Typography.headline)
                    Text(line.detail)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.secondaryText)
                }
                Spacer()
                Text(line.up ? "UP" : "DOWN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(line.up ? Color.green : Color.red)
            }
        }
    }

    private func runProbes() async {
        let client = session.graphQL
        var next: [ConsoleLine] = []

        // GraphQL + auth sanity (same stack as the app)
        if simulateGraphQLDown {
            next.append(ConsoleLine(id: "gql", name: "GraphQL API", up: false, detail: "Simulated down on this device.", latencyMs: 0))
        } else {
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await PreluraAdminAPI.viewMe(client: client)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                next.append(ConsoleLine(id: "gql", name: "GraphQL API", up: true, detail: "viewMe OK · \(ms) ms", latencyMs: ms))
            } catch {
                next.append(ConsoleLine(id: "gql", name: "GraphQL API", up: false, detail: error.localizedDescription, latencyMs: 0))
            }
        }

        if simulateAnalyticsDown {
            next.append(ConsoleLine(id: "an", name: "Analytics", up: false, detail: "Simulated down.", latencyMs: 0))
        } else {
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await PreluraAdminAPI.analyticsOverview(client: client)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                next.append(ConsoleLine(id: "an", name: "Analytics", up: true, detail: "analyticsOverview OK · \(ms) ms", latencyMs: ms))
            } catch {
                next.append(ConsoleLine(id: "an", name: "Analytics", up: false, detail: error.localizedDescription, latencyMs: 0))
            }
        }

        if simulateReportsDown {
            next.append(ConsoleLine(id: "rp", name: "Reports", up: false, detail: "Simulated down.", latencyMs: 0))
        } else {
            let t0 = CFAbsoluteTimeGetCurrent()
            do {
                _ = try await PreluraAdminAPI.allReports(client: client)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                next.append(ConsoleLine(id: "rp", name: "Reports", up: true, detail: "allReports OK · \(ms) ms", latencyMs: ms))
            } catch {
                next.append(ConsoleLine(id: "rp", name: "Reports", up: false, detail: error.localizedDescription, latencyMs: 0))
            }
        }

        if simulatePublicWebDown {
            next.append(ConsoleLine(id: "web", name: "Public web", up: false, detail: "Simulated down.", latencyMs: 0))
        } else {
            let t0 = CFAbsoluteTimeGetCurrent()
            let host = URL(string: Constants.publicWebBaseURL)?.host ?? "prelura.uk"
            var req = URLRequest(url: URL(string: Constants.publicWebBaseURL)!)
            req.httpMethod = "HEAD"
            req.timeoutInterval = 8
            do {
                let (_, resp) = try await URLSession.shared.data(for: req)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let up = (200 ... 399).contains(code) || code == 405 // some hosts reject HEAD
                next.append(
                    ConsoleLine(
                        id: "web",
                        name: "Public web",
                        up: up,
                        detail: up ? "\(host) responded · \(ms) ms (HEAD \(code))" : "HTTP \(code)",
                        latencyMs: ms
                    )
                )
            } catch {
                next.append(ConsoleLine(id: "web", name: "Public web", up: false, detail: error.localizedDescription, latencyMs: 0))
            }
        }

        lines = next
        lastProbeAt = Date()
    }
}

private struct ConsoleLine: Identifiable, Hashable {
    let id: String
    let name: String
    let up: Bool
    let detail: String
    let latencyMs: Int
}
