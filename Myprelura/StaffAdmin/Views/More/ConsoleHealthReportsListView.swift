import SwiftUI

/// Historical console runs (stored on device).
struct ConsoleHealthReportsListView: View {
    @State private var entries: [ConsoleHealthReportEntry] = []

    var body: some View {
        List {
            if entries.isEmpty {
                Text("No saved reports yet. Run a probe from Console (or enable background checks).")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)
                    .listRowBackground(Color.clear)
            }
            ForEach(entries) { e in
                NavigationLink {
                    ConsoleHealthReportDetailView(entry: e)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.startedAt.formatted(date: .abbreviated, time: .standard))
                            .font(Theme.Typography.headline)
                        Text(e.summaryLine)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                        HStack(spacing: 8) {
                            if e.hadDown {
                                Text("DOWN")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.red)
                            }
                            if e.hadDegraded {
                                Text("SLOW")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Color.yellow)
                            }
                            Text("\(e.checks.count) checks")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
            }
        }
        .navigationTitle("Console reports")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .onAppear { entries = ConsoleHealthReportStore.load() }
    }
}

private struct ConsoleHealthReportDetailView: View {
    let entry: ConsoleHealthReportEntry

    var body: some View {
        List {
            Section("Summary") {
                LabeledContent("Started", value: entry.startedAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Finished", value: entry.finishedAt.formatted(date: .abbreviated, time: .standard))
                Text(entry.summaryLine)
                    .font(Theme.Typography.footnote)
            }
            Section("Checks") {
                ForEach(entry.checks, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(c.title)
                                .font(Theme.Typography.headline)
                            Spacer()
                            Text(c.tier.uppercased())
                                .font(.caption.weight(.bold))
                                .foregroundStyle(tierColor(c.tier))
                        }
                        Text("\(c.section) · \(c.latencyMs) ms")
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Text(c.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Report detail")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
    }

    private func tierColor(_ raw: String) -> Color {
        switch raw.lowercased() {
        case "healthy": return .green
        case "degraded": return .yellow
        case "down": return .red
        default: return .gray
        }
    }
}
