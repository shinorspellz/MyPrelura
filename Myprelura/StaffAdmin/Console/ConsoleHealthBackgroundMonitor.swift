import Foundation
import UserNotifications

/// Runs console probes on an interval while the app stays eligible to run, persists a **report**, and posts **local** notifications (tap opens Console via `AppRouter`).
/// **Myprelura target only** (standard `UserDefaults`, not shared with the consumer app). **Superuser** sessions only — staff accounts never get the 30‑minute loop or alerts.
@MainActor
final class ConsoleHealthBackgroundMonitor {
    static let shared = ConsoleHealthBackgroundMonitor()

    static let kEnabled = "myprelura.console.bgMonitorEnabled"
    private static let kLastProbeAt = "myprelura.console.bgMonitorLastAt"
    static let notificationCategoryId = "myprelura.console.health"
    static let notificationIdentifierPrefix = "myprelura.console.health."

    private var loopTask: Task<Void, Never>?
    private weak var session: AdminSession?

    private init() {}

    func attach(session: AdminSession) {
        self.session = session
        if isEnabled, !mayRunScheduledProbes {
            UserDefaults.standard.set(false, forKey: Self.kEnabled)
        }
        reconcileLoopState()
    }

    /// Call when the user signs out so the timer stops and we drop the session reference.
    func detachOnSignOut() {
        session = nil
        stopLoop()
    }

    private var mayRunScheduledProbes: Bool {
        guard let session, session.isSignedIn, session.isSuperuser else { return false }
        return true
    }

    private func reconcileLoopState() {
        guard isEnabled, mayRunScheduledProbes else {
            stopLoop()
            return
        }
        startLoop()
    }

    func setEnabled(_ on: Bool) {
        if on {
            guard mayRunScheduledProbes else { return }
            requestNotificationPermissionIfNeeded()
        }
        UserDefaults.standard.set(on, forKey: Self.kEnabled)
        if on {
            reconcileLoopState()
            Task { await runNowIfEligible(reason: "enabled") }
        } else {
            stopLoop()
        }
    }

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.kEnabled)
    }

    func onAppBecameActive() {
        guard isEnabled else { return }
        Task { await runIfIntervalElapsed() }
    }

    private func startLoop() {
        stopLoop()
        loopTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
                await self.runIfIntervalElapsed()
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
    }

    private func runIfIntervalElapsed() async {
        guard isEnabled, mayRunScheduledProbes, let session else { return }
        let last = UserDefaults.standard.double(forKey: Self.kLastProbeAt)
        let now = Date().timeIntervalSince1970
        if now - last < 30 * 60 - 2 { return }
        await runProbe(session: session, persistAndNotify: true)
    }

    private func runNowIfEligible(reason: String) async {
        guard isEnabled, mayRunScheduledProbes, let session else { return }
        await runProbe(session: session, persistAndNotify: true)
    }

    private func runProbe(session: AdminSession, persistAndNotify: Bool) async {
        guard session.isSuperuser else { return }
        let sim = ConsoleSimulationFlags(
            graphql: false, analytics: false, reports: false, publicWeb: false,
            websocket: false, cdn: false, auth: false, messaging: false, listings: false,
            payments: false, push: false, search: false, ai: false, flows: false
        )
        let t0 = Date()
        let checks = await ConsoleHealthEngine.runAll(
            graphQL: session.graphQL,
            refreshToken: session.refreshToken,
            simulation: sim
        )
        let t1 = Date()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.kLastProbeAt)
        guard persistAndNotify else { return }
        ConsoleHealthReportStore.appendRun(checks: checks, startedAt: t0, finishedAt: t1)
        let down = checks.contains { $0.tier == .down }
        scheduleLocalNotification(checks: checks, hadDown: down)
    }

    private func scheduleLocalNotification(checks: [ConsoleHealthCheck], hadDown: Bool) {
        guard mayRunScheduledProbes else { return }
        let downTitles = checks.filter { $0.tier == .down }.map(\.title)
        let deg = checks.filter { $0.tier == .degraded }.count

        let title: String
        let body: String
        if hadDown {
            title = "Myprelura: health checks failing"
            body = downTitles.prefix(3).joined(separator: " · ").prefix(200).description
                + (downTitles.count > 3 ? "…" : "")
        } else {
            title = "Myprelura: all checks OK"
            body = deg > 0 ? "No outages. \(deg) check(s) slow or degraded — open Console for details." : "No outages detected. Open Console for the full report."
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = [
            "myprelura_open_console": true,
            "page": "STAFF_CONSOLE",
        ]
        content.categoryIdentifier = Self.notificationCategoryId

        let id = Self.notificationIdentifierPrefix + UUID().uuidString
        let req = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req) { _ in }
    }

    private func requestNotificationPermissionIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }
}
