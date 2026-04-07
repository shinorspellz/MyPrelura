import SwiftUI

/// Internal ops: **Real app health** probes (infrastructure, core systems, user flows), local outage simulation, optional Slack/Discord webhooks, and failure replay.
struct ConsoleView: View {
    @Environment(AdminSession.self) private var session
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @AppStorage("myprelura.console.sim.graphql") private var simulateGraphQLDown = false
    @AppStorage("myprelura.console.sim.analytics") private var simulateAnalyticsDown = false
    @AppStorage("myprelura.console.sim.reports") private var simulateReportsDown = false
    @AppStorage("myprelura.console.sim.publicWeb") private var simulatePublicWebDown = false
    @AppStorage("myprelura.console.sim.websocket") private var simulateWebSocketDown = false
    @AppStorage("myprelura.console.sim.cdn") private var simulateCDNDown = false
    @AppStorage("myprelura.console.sim.auth") private var simulateAuthDown = false
    @AppStorage("myprelura.console.sim.messaging") private var simulateMessagingDown = false
    @AppStorage("myprelura.console.sim.listings") private var simulateListingsDown = false
    @AppStorage("myprelura.console.sim.payments") private var simulatePaymentsDown = false
    @AppStorage("myprelura.console.sim.push") private var simulatePushDown = false
    @AppStorage("myprelura.console.sim.search") private var simulateSearchDown = false
    @AppStorage("myprelura.console.sim.ai") private var simulateAIDown = false
    @AppStorage("myprelura.console.sim.flows") private var simulateFlowsDown = false

    @AppStorage("myprelura.console.alertWebhookURL") private var alertWebhookURL = ""
    @AppStorage("myprelura.console.alertEnabled") private var alertEnabled = false
    @AppStorage("myprelura.console.lastAlertAt") private var lastAlertAtRaw = 0.0

    @State private var checks: [ConsoleHealthCheck] = []
    @State private var lastProbeAt: Date?
    @State private var isProbing = false
    @State private var replayItem: ReplaySheetItem?
    @State private var probeError: String?
    @State private var showBackgroundNotificationsSheet = false

    private var stripGridMinWidth: CGFloat {
        if AdminLayout.prefersDesktopNavigation { return 88 }
        return horizontalSizeClass == .regular ? 80 : 68
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                Text("Private probe runs when you open this screen (and on pull-to-refresh). Simulated outages only affect this device.")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.Colors.secondaryText)

                probeStatusHeader

                impactStripGrid

                if let lastProbeAt {
                    Text("Last probe: \(lastProbeAt.formatted(date: .omitted, time: .standard))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }

                if let probeError {
                    Text(probeError)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.error)
                }

                Text(ConsoleHealthEngine.userImpactLine(from: checks, isProbing: isProbing))
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.secondaryText)

                ForEach(ConsoleHealthSection.allCases) { section in
                    sectionBlock(section)
                }

                alertConfigCard

                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Simulate outage (local)")
                            .font(Theme.Typography.headline)
                        Text("Infrastructure")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                        Toggle("GraphQL API", isOn: $simulateGraphQLDown)
                        Toggle("WebSocket (inbox)", isOn: $simulateWebSocketDown)
                        Toggle("CDN / API host", isOn: $simulateCDNDown)
                        Toggle("Public web (wearhouse.co.uk)", isOn: $simulatePublicWebDown)
                        Toggle("Analytics field", isOn: $simulateAnalyticsDown)
                        Toggle("Reports field", isOn: $simulateReportsDown)
                        Text("Core + flows")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.tertiaryText)
                            .padding(.top, 4)
                        Toggle("Auth suite", isOn: $simulateAuthDown)
                        Toggle("Messaging", isOn: $simulateMessagingDown)
                        Toggle("Listings", isOn: $simulateListingsDown)
                        Toggle("Payments", isOn: $simulatePaymentsDown)
                        Toggle("Push", isOn: $simulatePushDown)
                        Toggle("Search", isOn: $simulateSearchDown)
                        Toggle("AI / recommend", isOn: $simulateAIDown)
                        Toggle("User flows (buy/sell/chat)", isOn: $simulateFlowsDown)
                    }
                }
            }
            .padding()
            .adminDesktopReadableWidth()
        }
        .background(Theme.Colors.background)
        .navigationTitle("Console")
        .navigationBarTitleDisplayMode(.inline)
        .adminNavigationChrome()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showBackgroundNotificationsSheet = true
                } label: {
                    NotificationToolbarBellVisual(
                        emphasized: ConsoleHealthBackgroundMonitor.shared.isEnabled
                    )
                }
                .accessibilityLabel("Background checks and notifications")
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    ConsoleHealthReportsListView()
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("Console reports")
            }
        }
        .sheet(isPresented: $showBackgroundNotificationsSheet) {
            ConsoleBackgroundNotificationsSheet()
                .environment(session)
        }
        .refreshable { await runProbes() }
        .task {
            if checks.isEmpty {
                checks = ConsoleHealthEngine.consoleProbeBlueprint
            }
            await runProbes()
        }
        .sheet(item: $replayItem) { item in
            NavigationStack {
                FailureReplaySheet(check: item.wrapped)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { replayItem = nil }
                        }
                    }
            }
        }
    }

    private var probeStatusHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            if isProbing {
                ProgressView()
                    .controlSize(.regular)
                Text("Running probes…")
                    .font(Theme.Typography.subheadline.weight(.medium))
                    .foregroundStyle(Theme.Colors.primaryText)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(Theme.Colors.tertiaryText)
                Text("Ready — pull to refresh or wait for the next background run.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var impactStripGrid: some View {
        let columns = [GridItem(.adaptive(minimum: stripGridMinWidth, maximum: 120), spacing: 12, alignment: .center)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            ForEach(ConsoleHealthEngine.consoleStripPrimaryCheckIds, id: \.self) { checkId in
                let tier = ConsoleHealthEngine.tierForStripCheck(id: checkId, checks: checks)
                stripColumn(
                    tier: tier,
                    title: ConsoleHealthEngine.stripShortTitle(forCheckId: checkId)
                )
            }
            let infraTier = ConsoleHealthEngine.sectionAggregate(.infrastructure, checks: checks)
            let infraDisplay: ConsoleHealthTier = checks.contains(where: { $0.section == .infrastructure && $0.tier == .pending }) ? .pending : infraTier
            stripColumn(tier: infraDisplay, title: "Infra")
        }
        .padding(.vertical, 8)
    }

    private func stripColumn(tier: ConsoleHealthTier, title: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(tier == .pending ? Theme.Colors.glassBackground : tier.color.opacity(0.25))
                    .frame(width: 28, height: 28)
                if tier == .pending {
                    ProgressView()
                        .scaleEffect(0.65)
                } else {
                    Circle()
                        .fill(tier.color)
                        .frame(width: 18, height: 18)
                        .shadow(color: tier.color.opacity(0.45), radius: 5)
                }
            }
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.Colors.secondaryText.opacity(0.35))
                .frame(width: 5, height: 20)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.tertiaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(minWidth: 56, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }

    private var alertConfigCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Auto alerts (Slack / Discord)")
                    .font(Theme.Typography.headline)
                Toggle("Send webhook when a probe is DOWN", isOn: $alertEnabled)
                TextField("Webhook URL (Slack incoming or Discord)", text: $alertWebhookURL)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("Slack: uses `{\"text\":\"…\"}`. Discord: same host expects `content` — paste a Discord webhook and we send JSON with a `content` field automatically when the host contains discord.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.tertiaryText)
            }
        }
    }

    @ViewBuilder
    private func sectionBlock(_ section: ConsoleHealthSection) -> some View {
        let rows = checks.filter { $0.section == section }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(section.rawValue)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Colors.primaryText)
                ForEach(rows) { row in
                    statusRow(row)
                }
            }
        }
    }

    private func statusRow(_ row: ConsoleHealthCheck) -> some View {
        Button {
            if row.tier == .down || row.tier == .degraded {
                replayItem = ReplaySheetItem(wrapped: row)
            }
        } label: {
            GlassCard {
                HStack(alignment: .top, spacing: 10) {
                    if row.tier == .pending {
                        ProgressView()
                            .scaleEffect(0.85)
                            .padding(.top, 2)
                    } else {
                        Circle()
                            .fill(row.tier.color)
                            .frame(width: 12, height: 12)
                            .padding(.top, 4)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Colors.primaryText)
                        Text(row.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        if row.tier == .down || row.tier == .degraded {
                            Text("Tap for replay (request / response / timeline)")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(row.tier.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(row.tier == .pending ? Theme.Colors.tertiaryText : row.tier.color)
                        if row.latencyMs > 0 {
                            Text("\(row.latencyMs) ms")
                                .font(.caption2)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(row.tier == .pending || (row.tier != .down && row.tier != .degraded))
    }

    private func runProbes() async {
        guard !isProbing else { return }
        isProbing = true
        probeError = nil
        checks = ConsoleHealthEngine.consoleProbeBlueprint

        let sim = ConsoleSimulationFlags(
            graphql: simulateGraphQLDown,
            analytics: simulateAnalyticsDown,
            reports: simulateReportsDown,
            publicWeb: simulatePublicWebDown,
            websocket: simulateWebSocketDown,
            cdn: simulateCDNDown,
            auth: simulateAuthDown,
            messaging: simulateMessagingDown,
            listings: simulateListingsDown,
            payments: simulatePaymentsDown,
            push: simulatePushDown,
            search: simulateSearchDown,
            ai: simulateAIDown,
            flows: simulateFlowsDown
        )

        let client = session.graphQL
        let tProbeStart = Date()

        await ConsoleHealthEngine.runSequential(
            graphQL: client,
            refreshToken: session.refreshToken,
            simulation: sim
        ) { check in
            if let i = checks.firstIndex(where: { $0.id == check.id }) {
                checks[i] = check
            }
        }

        let tProbeEnd = Date()
        lastProbeAt = tProbeEnd
        isProbing = false
        ConsoleHealthReportStore.appendRun(checks: checks, startedAt: tProbeStart, finishedAt: tProbeEnd)

        await sendAlertsIfNeeded(for: checks)
    }

    private func sendAlertsIfNeeded(for rows: [ConsoleHealthCheck]) async {
        guard alertEnabled else { return }
        let downs = rows.filter { $0.tier == .down }
        guard !downs.isEmpty else { return }
        let trimmed = alertWebhookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), !trimmed.isEmpty else { return }

        let now = Date().timeIntervalSince1970
        if now - lastAlertAtRaw < 90 { return }

        let title = "Myprelura Console: \(downs.count) check(s) DOWN"
        let body = downs.map { "• \($0.title): \($0.detail)" }.joined(separator: "\n")
        let payload: [String: Any]
        if url.host?.contains("discord") == true {
            payload = ["content": "\(title)\n\(body)".prefix(1800).description]
        } else {
            payload = ["text": "\(title)\n\(body)".prefix(8000).description]
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if (200 ... 299).contains(code) {
                lastAlertAtRaw = now
            } else {
                probeError = "Alert webhook HTTP \(code)"
            }
        } catch {
            probeError = "Alert webhook: \(error.localizedDescription)"
        }
    }
}

// MARK: - Background notifications (toolbar sheet)

private struct ConsoleBackgroundNotificationsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AdminSession.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Background checks & notifications")
                                .font(Theme.Typography.headline)
                            Toggle(
                                "Ping every ~30 min while the app can run, notify if anything is down (or all OK)",
                                isOn: Binding(
                                    get: { ConsoleHealthBackgroundMonitor.shared.isEnabled },
                                    set: { ConsoleHealthBackgroundMonitor.shared.setEnabled($0) }
                                )
                            )
                            .disabled(!session.isSuperuser)
                            Text("Superuser (Admin) accounts only. Alerts are local to the Myprelura app on this device — not the consumer Prelura app.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                            Text("iOS may pause the app when it is backgrounded; opening the app also runs a check if the interval has passed. Each run is saved under Console reports.")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.tertiaryText)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .adminDesktopReadableWidth()
            }
            .background(Theme.Colors.background)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .adminNavigationChrome()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            ConsoleHealthBackgroundMonitor.shared.attach(session: session)
        }
    }
}

// MARK: - Replay sheet

private struct ReplaySheetItem: Identifiable {
    var id: String { wrapped.id }
    let wrapped: ConsoleHealthCheck
}

private struct FailureReplaySheet: View {
    let check: ConsoleHealthCheck

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(check.title)
                    .font(.title3.weight(.semibold))
                Label(check.tier.label, systemImage: "circle.fill")
                    .foregroundStyle(check.tier.color)
                Text(check.detail)
                    .font(.body)
                    .foregroundStyle(Theme.Colors.secondaryText)

                Group {
                    Text("Request")
                        .font(.headline)
                    Text(check.requestSummary)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.Colors.primaryText)
                }

                Group {
                    Text("Response / notes")
                        .font(.headline)
                    Text(check.responseSummary)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.Colors.primaryText)
                }

                Group {
                    Text("Timeline")
                        .font(.headline)
                    if check.timeline.isEmpty {
                        Text("—")
                            .foregroundStyle(Theme.Colors.tertiaryText)
                    } else {
                        ForEach(Array(check.timeline.enumerated()), id: \.offset) { _, line in
                            Text("• \(line)")
                                .font(.footnote)
                        }
                    }
                }

                if let last = check.lastMessageAt {
                    Text("Last inbound frame (WS): \(last.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.tertiaryText)
                }
                if check.reconnectAttempts > 0 {
                    Text("Reconnect attempts (probe window): \(check.reconnectAttempts)")
                        .font(.caption)
                }
                if let rate = check.deliverySuccessRate {
                    Text(String(format: "Delivery / frame success rate (heuristic): %.0f%%", rate * 100))
                        .font(.caption)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.Colors.background)
        .navigationTitle("Replay")
        .navigationBarTitleDisplayMode(.inline)
    }
}
