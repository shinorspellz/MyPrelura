import Foundation

/// One persisted row per automated or manual console run (snapshots only — no JWTs).
struct ConsoleHealthReportEntry: Codable, Identifiable, Hashable {
    let reportId: String
    var id: String { reportId }
    let startedAt: Date
    let finishedAt: Date
    let hadDown: Bool
    let hadDegraded: Bool
    let summaryLine: String
    let checks: [ConsoleHealthCheckSnapshot]

    init(reportId: String = UUID().uuidString, startedAt: Date, finishedAt: Date, hadDown: Bool, hadDegraded: Bool, summaryLine: String, checks: [ConsoleHealthCheckSnapshot]) {
        self.reportId = reportId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.hadDown = hadDown
        self.hadDegraded = hadDegraded
        self.summaryLine = summaryLine
        self.checks = checks
    }

    enum CodingKeys: String, CodingKey {
        case reportId, startedAt, finishedAt, hadDown, hadDegraded, summaryLine, checks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reportId = try c.decodeIfPresent(String.self, forKey: .reportId) ?? UUID().uuidString
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        hadDown = try c.decode(Bool.self, forKey: .hadDown)
        hadDegraded = try c.decode(Bool.self, forKey: .hadDegraded)
        summaryLine = try c.decode(String.self, forKey: .summaryLine)
        checks = try c.decode([ConsoleHealthCheckSnapshot].self, forKey: .checks)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reportId, forKey: .reportId)
        try c.encode(startedAt, forKey: .startedAt)
        try c.encode(finishedAt, forKey: .finishedAt)
        try c.encode(hadDown, forKey: .hadDown)
        try c.encode(hadDegraded, forKey: .hadDegraded)
        try c.encode(summaryLine, forKey: .summaryLine)
        try c.encode(checks, forKey: .checks)
    }
}

struct ConsoleHealthCheckSnapshot: Codable, Hashable {
    let id: String
    let section: String
    let title: String
    let tier: String
    let detail: String
    let latencyMs: Int
}

extension ConsoleHealthCheck {
    fileprivate var snapshot: ConsoleHealthCheckSnapshot {
        ConsoleHealthCheckSnapshot(
            id: id,
            section: section.rawValue,
            title: title,
            tier: tier.rawValue,
            detail: detail,
            latencyMs: latencyMs
        )
    }
}

enum ConsoleHealthReportStore {
    private static let key = "myprelura.console.reports.v1"
    private static let maxEntries = 50

    static func load() -> [ConsoleHealthReportEntry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([ConsoleHealthReportEntry].self, from: data)) ?? []
    }

    static func appendRun(checks: [ConsoleHealthCheck], startedAt: Date, finishedAt: Date) {
        let snaps = checks.map(\.snapshot)
        let down = checks.contains { $0.tier == .down }
        let degraded = checks.contains { $0.tier == .degraded }
        let downTitles = checks.filter { $0.tier == .down }.map(\.title).prefix(4).joined(separator: ", ")
        let summary: String
        if down {
            summary = downTitles.isEmpty ? "One or more checks DOWN." : "DOWN: \(downTitles)"
        } else if degraded {
            let n = checks.filter { $0.tier == .degraded }.count
            summary = "All up · \(n) slow/degraded check(s)."
        } else {
            summary = "All checks healthy (or N/A)."
        }
        let entry = ConsoleHealthReportEntry(
            reportId: UUID().uuidString,
            startedAt: startedAt,
            finishedAt: finishedAt,
            hadDown: down,
            hadDegraded: degraded,
            summaryLine: summary,
            checks: snaps
        )
        var all = load()
        all.insert(entry, at: 0)
        if all.count > maxEntries {
            all = Array(all.prefix(maxEntries))
        }
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
