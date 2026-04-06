import Foundation
import SwiftUI

// MARK: - Arbitrary JSON (verifyToken.payload)

/// Decodes graphql_jwt `verifyToken.payload` and similar scalars without a fixed schema.
private enum HealthJSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case object([String: HealthJSONValue])
    case array([HealthJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let v = try? c.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? c.decode(Int.self) {
            self = .int(v)
            return
        }
        if let v = try? c.decode(Double.self) {
            self = .double(v)
            return
        }
        if let v = try? c.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let v = try? c.decode([String: HealthJSONValue].self) {
            self = .object(v)
            return
        }
        if let v = try? c.decode([HealthJSONValue].self) {
            self = .array(v)
            return
        }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported JSON fragment")
    }
}

// MARK: - Models

enum ConsoleHealthSection: String, CaseIterable, Identifiable {
    case infrastructure = "Infrastructure"
    case core = "Core systems"
    case flows = "User flows"

    var id: String { rawValue }
}

enum ConsoleHealthTier: String {
    case healthy
    case degraded
    case down
    case skipped
    /// Row not yet executed in the current run (Console UI).
    case pending

    var label: String {
        switch self {
        case .healthy: return "OK"
        case .degraded: return "SLOW"
        case .down: return "DOWN"
        case .skipped: return "N/A"
        case .pending: return "…"
        }
    }

    var color: Color {
        switch self {
        case .healthy: return .green
        case .degraded: return .yellow
        case .down: return .red
        case .skipped: return .gray
        case .pending: return .gray
        }
    }

    var isFailure: Bool { self == .down }

    var aggregateRank: Int {
        switch self {
        case .down: return 3
        case .degraded: return 2
        case .healthy: return 1
        case .skipped: return 0
        case .pending: return 0
        }
    }
}

struct ConsoleHealthCheck: Identifiable {
    let id: String
    let section: ConsoleHealthSection
    let title: String
    var tier: ConsoleHealthTier
    var detail: String
    var latencyMs: Int
    var requestSummary: String
    var responseSummary: String
    var timeline: [String]
    /// WebSocket / messaging: last inbound frame time (if any)
    var lastMessageAt: Date?
    /// Synthetic: reconnect attempts observed in this probe window
    var reconnectAttempts: Int
    /// 0...1 where applicable
    var deliverySuccessRate: Double?
}

struct ConsoleSimulationFlags {
    var graphql: Bool
    var analytics: Bool
    var reports: Bool
    var publicWeb: Bool
    var websocket: Bool
    var cdn: Bool
    var auth: Bool
    var messaging: Bool
    var listings: Bool
    var payments: Bool
    var push: Bool
    var search: Bool
    var ai: Bool
    var flows: Bool
}

// MARK: - Thresholds

private enum HealthThresholds {
    static let gqlSlowMs = 750
    static let searchSlowMs = 650
    static let wsOpenSlowMs = 2_500
    static let httpSlowMs = 900
    static let msgRoundTripSlowMs = 2_000
}

// MARK: - Engine

@MainActor
enum ConsoleHealthEngine {

    static func userImpactLine(from checks: [ConsoleHealthCheck], isProbing: Bool = false) -> String {
        if isProbing {
            return "Running probes — rows update one by one from the top."
        }
        let relevant = checks.filter { $0.tier != .skipped && $0.tier != .pending }
        guard !relevant.isEmpty else { return "No finished probes yet." }
        let down = relevant.filter { $0.tier == .down }.count
        let slow = relevant.filter { $0.tier == .degraded }.count
        let pctDown = Int((Double(down) / Double(relevant.count) * 100).rounded())
        if down == 0, slow == 0 {
            return "Impact: low — all checked paths healthy."
        }
        if down > 0 {
            return "Impact: elevated — \(down)/\(relevant.count) checks down (~\(pctDown)% of probes). Review Core + Flows first."
        }
        return "Impact: moderate — \(slow)/\(relevant.count) checks slow (latency or partial paths)."
    }

    static func sectionAggregate(_ section: ConsoleHealthSection, checks: [ConsoleHealthCheck]) -> ConsoleHealthTier {
        let rows = checks.filter { $0.section == section && $0.tier != .skipped && $0.tier != .pending }
        guard !rows.isEmpty else { return .skipped }
        return rows.map(\.tier).max(by: { $0.aggregateRank < $1.aggregateRank }) ?? .healthy
    }

    /// Placeholder rows for the Console (same order as `emitEachProbe`).
    static var consoleProbeBlueprint: [ConsoleHealthCheck] {
        func p(_ id: String, _ section: ConsoleHealthSection, _ title: String) -> ConsoleHealthCheck {
            ConsoleHealthCheck(
                id: id,
                section: section,
                title: title,
                tier: .pending,
                detail: "Waiting for probe…",
                latencyMs: 0,
                requestSummary: "",
                responseSummary: "",
                timeline: [],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        var rows: [ConsoleHealthCheck] = []
        rows.append(contentsOf: [
            p("infra_gql", .infrastructure, "GraphQL API"),
            p("infra_analytics", .infrastructure, "Analytics field"),
            p("infra_reports", .infrastructure, "Reports field"),
            p("infra_web", .infrastructure, "Public web"),
            p("infra_ws", .infrastructure, "WebSocket (inbox)"),
            p("infra_cdn", .infrastructure, "CDN / edge (API host)"),
        ])
        rows.append(contentsOf: [
            p("core_auth_login", .core, "Auth · login path"),
            p("core_auth_signup", .core, "Auth · signup path"),
            p("core_auth_refresh", .core, "Auth · token refresh"),
            p("core_auth_session", .core, "Auth · session (viewMe)"),
            p("core_auth_verify_jwt", .core, "Auth · JWT verify"),
            p("core_msg_inbox", .core, "Messaging · inbox"),
            p("core_msg_roundtrip", .core, "Messaging · send + persistence"),
            p("core_list_fetch", .core, "Listings · fetch (staff)"),
            p("core_list_create", .core, "Listings · create (probe)"),
            p("core_list_delete", .core, "Listings · delete (probe)"),
            p("core_list_publish_metric", .core, "Listings · publish latency est."),
            p("core_pay_intent", .core, "Payments · intent"),
            p("core_pay_confirm", .core, "Payments · confirm"),
            p("core_pay_webhook", .core, "Payments · webhooks"),
            p("core_pay_last_ok", .core, "Payments · last success (heuristic)"),
            p("core_pay_failed_detect", .core, "Payments · failed detection"),
            p("core_push_send", .core, "Push · send (debug)"),
            p("core_push_token", .core, "Push · device token (local)"),
            p("core_push_delivery", .core, "Push · delivery confirm"),
            p("core_search_q", .core, "Search · query"),
            p("core_search_empty", .core, "Search · empty guard"),
            p("core_media_upload", .core, "Media · upload endpoint"),
            p("core_media_image", .core, "Media · listing image fetch"),
            p("core_ai_rec", .core, "AI · recommendations"),
            p("core_ai_mod", .core, "AI · moderation"),
            p("core_ai_price", .core, "AI · pricing hints"),
        ])
        rows.append(contentsOf: [
            p("flow_buy", .flows, "Flow · buy path"),
            p("flow_sell", .flows, "Flow · sell path"),
            p("flow_chat", .flows, "Flow · chat path"),
        ])
        return rows
    }

    /// Seven headline probes in the Console status strip, then an **Infrastructure** summary pill (worst tier of all infrastructure checks).
    static let consoleStripPrimaryCheckIds: [String] = [
        "infra_gql",
        "infra_analytics",
        "infra_reports",
        "infra_web",
        "infra_ws",
        "infra_cdn",
        "core_media_upload",
    ]

    static func tierForStripCheck(id: String, checks: [ConsoleHealthCheck]) -> ConsoleHealthTier {
        guard let row = checks.first(where: { $0.id == id }) else { return .pending }
        return row.tier
    }

    static func stripShortTitle(forCheckId id: String) -> String {
        switch id {
        case "infra_gql": return "GraphQL"
        case "infra_analytics": return "Analytics"
        case "infra_reports": return "Reports"
        case "infra_web": return "Web"
        case "infra_ws": return "WS"
        case "infra_cdn": return "CDN"
        case "core_media_upload": return "Media"
        default: return "?"
        }
    }

    /// Emits each probe as it completes (same order as `runAll`).
    static func runSequential(
        graphQL: GraphQLClient,
        refreshToken: String?,
        simulation: ConsoleSimulationFlags,
        onEach: @escaping (ConsoleHealthCheck) async -> Void
    ) async {
        await emitEachProbe(graphQL: graphQL, refreshToken: refreshToken, simulation: simulation, emit: onEach)
    }

    private static func emitEachProbe(
        graphQL: GraphQLClient,
        refreshToken: String?,
        simulation: ConsoleSimulationFlags,
        emit: (ConsoleHealthCheck) async -> Void
    ) async {
        // —— Infrastructure (order matches Console status strip + detail list) ——
        await emit(await probeGraphQL(graphQL: graphQL, sim: simulation.graphql))
        await emit(await probeAnalytics(graphQL: graphQL, sim: simulation.analytics))
        await emit(await probeReports(graphQL: graphQL, sim: simulation.reports))
        await emit(await probePublicWeb(sim: simulation.publicWeb))
        await emit(await probeWebSocketInbox(refreshToken: refreshToken, sim: simulation.websocket))
        await emit(await probeCDN(sim: simulation.cdn))

        // —— Core ——
        for row in await probeAuthSuite(graphQL: graphQL, refreshToken: refreshToken, sim: simulation.auth) { await emit(row) }
        for row in await probeMessagingSuite(graphQL: graphQL, sim: simulation.messaging) { await emit(row) }
        for row in await probeListingsSuite(graphQL: graphQL, sim: simulation.listings) { await emit(row) }
        for row in await probePaymentsSuite(graphQL: graphQL, sim: simulation.payments) { await emit(row) }
        for row in await probePushSuite(graphQL: graphQL, sim: simulation.push) { await emit(row) }
        for row in await probeSearchSuite(graphQL: graphQL, sim: simulation.search) { await emit(row) }
        for row in await probeMediaSuite(graphQL: graphQL, sim: simulation.cdn) { await emit(row) }
        for row in await probeAISuite(graphQL: graphQL, sim: simulation.ai) { await emit(row) }

        // —— Flows ——
        for row in await probeUserFlows(graphQL: graphQL, sim: simulation.flows) { await emit(row) }
    }

    static func runAll(
        graphQL: GraphQLClient,
        refreshToken: String?,
        simulation: ConsoleSimulationFlags
    ) async -> [ConsoleHealthCheck] {
        var out: [ConsoleHealthCheck] = []
        await emitEachProbe(graphQL: graphQL, refreshToken: refreshToken, simulation: simulation) { row in
            out.append(row)
        }
        return out
    }

    // MARK: Infrastructure probes

    private static func probeGraphQL(graphQL: GraphQLClient, sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = []
        let t0 = CFAbsoluteTimeGetCurrent()
        tl.append("start viewMe")
        if sim {
            return ConsoleHealthCheck(
                id: "infra_gql",
                section: .infrastructure,
                title: "GraphQL API",
                tier: .down,
                detail: "Simulated down on this device.",
                latencyMs: 0,
                requestSummary: "POST \(Constants.graphQLBaseURL) query ViewMe",
                responseSummary: "(simulated)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        do {
            _ = try await PreluraAdminAPI.viewMe(client: graphQL)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            tl.append("viewMe OK")
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            return ConsoleHealthCheck(
                id: "infra_gql",
                section: .infrastructure,
                title: "GraphQL API",
                tier: tier,
                detail: "viewMe OK · \(ms) ms",
                latencyMs: ms,
                requestSummary: "POST \(Constants.graphQLBaseURL)\nquery ViewMe { }",
                responseSummary: "HTTP 200, data.viewMe present",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            tl.append("error: \(error.localizedDescription)")
            return ConsoleHealthCheck(
                id: "infra_gql",
                section: .infrastructure,
                title: "GraphQL API",
                tier: .down,
                detail: error.localizedDescription,
                latencyMs: ms,
                requestSummary: "POST \(Constants.graphQLBaseURL)\nquery ViewMe",
                responseSummary: String(describing: error),
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
    }

    private static func probeWebSocketInbox(refreshToken: String?, sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = ["open ws/conversations/"]
        if sim {
            return ConsoleHealthCheck(
                id: "infra_ws",
                section: .infrastructure,
                title: "WebSocket (inbox)",
                tier: .down,
                detail: "Simulated down on this device.",
                latencyMs: 0,
                requestSummary: "WSS \(Constants.conversationsWebSocketURL)\nAuthorization: Token …",
                responseSummary: "(simulated)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        guard let tok = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), !tok.isEmpty else {
            return ConsoleHealthCheck(
                id: "infra_ws",
                section: .infrastructure,
                title: "WebSocket (inbox)",
                tier: .skipped,
                detail: "No refresh token — cannot auth WS (sync staff session).",
                latencyMs: 0,
                requestSummary: "WSS \(Constants.conversationsWebSocketURL)",
                responseSummary: "—",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        let result = await WebSocketHandshakeProbe.probeConversationsChannel(token: tok, waitForFrameSeconds: 3.5)
        tl.append(contentsOf: result.timeline)
        let tier: ConsoleHealthTier
        if !result.connected {
            tier = .down
        } else if result.openMs >= HealthThresholds.wsOpenSlowMs || result.silentConnected {
            tier = .degraded
        } else {
            tier = .healthy
        }
        var detail = "Connected in \(result.openMs) ms"
        if let f = result.firstFrameMs {
            detail += " · first frame \(f) ms"
        } else if result.connected {
            detail += " · no frame in window (possible silent channel)"
        }
        if result.reconnects > 0 {
            detail += " · reconnects \(result.reconnects)"
        }
        let delivery: Double? = result.framesReceived > 0 ? 1.0 : (result.connected ? 0.0 : nil)
        return ConsoleHealthCheck(
            id: "infra_ws",
            section: .infrastructure,
            title: "WebSocket (inbox)",
            tier: tier,
            detail: detail,
            latencyMs: result.openMs,
            requestSummary: "WSS \(Constants.conversationsWebSocketURL)\nAuthorization: Token <refresh>",
            responseSummary: "frames=\(result.framesReceived) silent=\(result.silentConnected)",
            timeline: tl,
            lastMessageAt: result.lastFrameAt,
            reconnectAttempts: result.reconnects,
            deliverySuccessRate: delivery
        )
    }

    private static func probeCDN(sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = ["HEAD API host"]
        if sim {
            return ConsoleHealthCheck(
                id: "infra_cdn",
                section: .infrastructure,
                title: "CDN / edge (API host)",
                tier: .down,
                detail: "Simulated down on this device.",
                latencyMs: 0,
                requestSummary: "HEAD https://prelura.voltislabs.uk/robots.txt",
                responseSummary: "(simulated)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        guard let url = URL(string: "https://prelura.voltislabs.uk/robots.txt") else {
            return ConsoleHealthCheck(id: "infra_cdn", section: .infrastructure, title: "CDN / edge (API host)", tier: .down, detail: "Bad URL", latencyMs: 0, requestSummary: "", responseSummary: "", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 8
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200 ... 399).contains(code) || code == 405
            let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.httpSlowMs ? .degraded : .healthy) : .down
            tl.append("HTTP \(code)")
            return ConsoleHealthCheck(
                id: "infra_cdn",
                section: .infrastructure,
                title: "CDN / edge (API host)",
                tier: tier,
                detail: ok ? "robots.txt · \(ms) ms (HEAD \(code))" : "HTTP \(code)",
                latencyMs: ms,
                requestSummary: "HEAD \(url.absoluteString)",
                responseSummary: "status=\(code)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        } catch {
            tl.append(error.localizedDescription)
            return ConsoleHealthCheck(
                id: "infra_cdn",
                section: .infrastructure,
                title: "CDN / edge (API host)",
                tier: .down,
                detail: error.localizedDescription,
                latencyMs: 0,
                requestSummary: "HEAD \(url.absoluteString)",
                responseSummary: String(describing: error),
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
    }

    private static func probePublicWeb(sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = ["HEAD public web"]
        if sim {
            return ConsoleHealthCheck(
                id: "infra_web",
                section: .infrastructure,
                title: "Public web",
                tier: .down,
                detail: "Simulated down on this device.",
                latencyMs: 0,
                requestSummary: "HEAD \(Constants.publicWebHealthProbeURL)",
                responseSummary: "(simulated)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
        guard let url = URL(string: Constants.publicWebHealthProbeURL) else {
            return ConsoleHealthCheck(id: "infra_web", section: .infrastructure, title: "Public web", tier: .down, detail: "Bad URL", latencyMs: 0, requestSummary: "", responseSummary: "", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 8
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200 ... 399).contains(code) || code == 405
            let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.httpSlowMs ? .degraded : .healthy) : .down
            tl.append("HTTP \(code)")
            let host = url.host ?? "site"
            return ConsoleHealthCheck(
                id: "infra_web",
                section: .infrastructure,
                title: "Public web",
                tier: tier,
                detail: ok ? "\(host) · \(ms) ms (HEAD \(code))" : "HTTP \(code)",
                latencyMs: ms,
                requestSummary: "HEAD \(url.absoluteString)",
                responseSummary: "status=\(code)",
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        } catch {
            return ConsoleHealthCheck(
                id: "infra_web",
                section: .infrastructure,
                title: "Public web",
                tier: .down,
                detail: error.localizedDescription,
                latencyMs: 0,
                requestSummary: "HEAD \(url.absoluteString)",
                responseSummary: String(describing: error),
                timeline: tl,
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            )
        }
    }

    private static func probeAnalytics(graphQL: GraphQLClient, sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = ["analyticsOverview"]
        if sim {
            return ConsoleHealthCheck(id: "infra_analytics", section: .infrastructure, title: "Analytics field", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "query analyticsOverview", responseSummary: "(simulated)", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await PreluraAdminAPI.analyticsOverview(client: graphQL)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            tl.append("ok")
            return ConsoleHealthCheck(id: "infra_analytics", section: .infrastructure, title: "Analytics field", tier: tier, detail: "analyticsOverview OK · \(ms) ms", latencyMs: ms, requestSummary: "query analyticsOverview", responseSummary: "HTTP 200", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            return ConsoleHealthCheck(id: "infra_analytics", section: .infrastructure, title: "Analytics field", tier: .down, detail: error.localizedDescription, latencyMs: ms, requestSummary: "query analyticsOverview", responseSummary: String(describing: error), timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
    }

    private static func probeReports(graphQL: GraphQLClient, sim: Bool) async -> ConsoleHealthCheck {
        var tl: [String] = ["allReports"]
        if sim {
            return ConsoleHealthCheck(id: "infra_reports", section: .infrastructure, title: "Reports field", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "query allReports", responseSummary: "(simulated)", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            _ = try await PreluraAdminAPI.allReports(client: graphQL)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            return ConsoleHealthCheck(id: "infra_reports", section: .infrastructure, title: "Reports field", tier: tier, detail: "allReports OK · \(ms) ms", latencyMs: ms, requestSummary: "query allReports", responseSummary: "HTTP 200", timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        } catch {
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            return ConsoleHealthCheck(id: "infra_reports", section: .infrastructure, title: "Reports field", tier: .down, detail: error.localizedDescription, latencyMs: ms, requestSummary: "query allReports", responseSummary: String(describing: error), timeline: tl, lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil)
        }
    }

    // MARK: Auth

    private static func probeAuthSuite(graphQL: GraphQLClient, refreshToken: String?, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_auth_login", section: .core, title: "Auth · login path", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: ["sim"], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_auth_signup", section: .core, title: "Auth · signup path", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: ["sim"], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_auth_refresh", section: .core, title: "Auth · token refresh", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: ["sim"], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_auth_session", section: .core, title: "Auth · session (viewMe)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: ["sim"], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_auth_verify_jwt", section: .core, title: "Auth · JWT verify", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: ["sim"], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        var checks: [ConsoleHealthCheck] = []

        // Login: wrong password → expect GraphQL errors (proves mutation + credential path alive)
        do {
            let q = """
            mutation HealthLogin($username: String!, $password: String!) {
              login(username: $username, password: $password) { token }
            }
            """
            struct Env: Decodable { let login: LoginTok? }
            struct LoginTok: Decodable { let token: String? }
            let t0 = CFAbsoluteTimeGetCurrent()
            let (data, errs) = try await graphQL.executeAllowingGraphQLErrors(
                query: q,
                variables: ["username": "__prelura_health_probe__", "password": "__bad__"],
                operationName: "HealthLogin",
                responseType: Env.self
            )
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let gotErr = !(errs ?? []).isEmpty
            let tokenNil = data?.login?.token == nil
            let tier: ConsoleHealthTier = (gotErr || tokenNil) ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
            let detail = gotErr ? "login rejected as expected · \(ms) ms" : "Unexpected success — check probe username"
            checks.append(ConsoleHealthCheck(
                id: "core_auth_login",
                section: .core,
                title: "Auth · login path",
                tier: tier,
                detail: detail,
                latencyMs: ms,
                requestSummary: "mutation HealthLogin(username: __prelura_health_probe__)",
                responseSummary: (errs ?? []).map(\.message).joined(separator: " | ").prefix(400).description,
                timeline: ["allowing-errors decode"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_auth_login", section: .core, title: "Auth · login path", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation HealthLogin", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Signup: mismatched passwords → should not create a user
        do {
            let q = """
            mutation HealthRegister($email: String!, $firstName: String!, $lastName: String!, $username: String!, $password1: String!, $password2: String!) {
              register(email: $email, firstName: $firstName, lastName: $lastName, username: $username, password1: $password1, password2: $password2) {
                success errors
              }
            }
            """
            struct Env: Decodable { let register: Reg? }
            struct Reg: Decodable { let success: Bool?; let errors: [String: [String]]? }
            let u = "hp_\(UUID().uuidString.prefix(8))"
            let t0 = CFAbsoluteTimeGetCurrent()
            let data = try await graphQL.execute(
                query: q,
                variables: [
                    "email": "\(u)@health.invalid",
                    "firstName": "H",
                    "lastName": "P",
                    "username": u,
                    "password1": "Alpha123!",
                    "password2": "Beta123!",
                ],
                operationName: "HealthRegister",
                responseType: Env.self
            )
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let okPath = data.register?.success != true
            let tier: ConsoleHealthTier = okPath ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
            let errStr = data.register?.errors.map { "\($0)" } ?? "success=\(data.register?.success ?? false)"
            checks.append(ConsoleHealthCheck(
                id: "core_auth_signup",
                section: .core,
                title: "Auth · signup path",
                tier: tier,
                detail: okPath ? "register validation path OK · \(ms) ms" : "Unexpected success",
                latencyMs: ms,
                requestSummary: "mutation HealthRegister (password mismatch)",
                responseSummary: String(errStr.prefix(400)),
                timeline: ["register"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_auth_signup", section: .core, title: "Auth · signup path", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation HealthRegister", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Refresh: uses long-running refresh token from staff session (does not persist new tokens here)
        if let r = refreshToken?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            do {
                let q = """
                mutation HealthRefresh($refreshToken: String!) {
                  refreshToken(refreshToken: $refreshToken) {
                    token
                    refreshToken
                  }
                }
                """
                struct Env: Decodable { let refreshToken: RT? }
                struct RT: Decodable { let token: String?; let refreshToken: String? }
                let t0 = CFAbsoluteTimeGetCurrent()
                let data = try await graphQL.execute(query: q, variables: ["refreshToken": r], operationName: "HealthRefresh", responseType: Env.self)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let ok = data.refreshToken?.token != nil
                let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .down
                checks.append(ConsoleHealthCheck(
                    id: "core_auth_refresh",
                    section: .core,
                    title: "Auth · token refresh",
                    tier: tier,
                    detail: ok ? "refreshToken OK · \(ms) ms (tokens not saved)" : "No token in payload",
                    latencyMs: ms,
                    requestSummary: "mutation HealthRefresh(refreshToken: <stored>)",
                    responseSummary: ok ? "new access token returned" : "missing token",
                    timeline: ["refresh"],
                    lastMessageAt: nil,
                    reconnectAttempts: 0,
                    deliverySuccessRate: nil
                ))
            } catch {
                checks.append(ConsoleHealthCheck(id: "core_auth_refresh", section: .core, title: "Auth · token refresh", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation HealthRefresh", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            }
        } else {
            checks.append(ConsoleHealthCheck(id: "core_auth_refresh", section: .core, title: "Auth · token refresh", tier: .skipped, detail: "No refresh token in session.", latencyMs: 0, requestSummary: "mutation HealthRefresh", responseSummary: "—", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Session validation
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let me = try await PreluraAdminAPI.viewMe(client: graphQL)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let ok = me != nil
            let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .down
            checks.append(ConsoleHealthCheck(
                id: "core_auth_session",
                section: .core,
                title: "Auth · session (viewMe)",
                tier: tier,
                detail: ok ? "session OK · \(ms) ms" : "viewMe nil",
                latencyMs: ms,
                requestSummary: "query ViewMe",
                responseSummary: ok ? "user id=\(me?.id ?? 0)" : "nil",
                timeline: ["viewMe"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_auth_session", section: .core, title: "Auth · session (viewMe)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "query ViewMe", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Verify JWT (graphql_jwt)
        if let access = graphQL.debugPeekAuthToken() {
            do {
                let q = """
                mutation HealthVerifyToken($token: String!) {
                  verifyToken(token: $token) {
                    payload
                  }
                }
                """
                struct Env: Decodable { let verifyToken: VP? }
                struct VP: Decodable { let payload: HealthJSONValue? }
                let t0 = CFAbsoluteTimeGetCurrent()
                let data = try await graphQL.execute(query: q, variables: ["token": access], operationName: "HealthVerifyToken", responseType: Env.self)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                let ok = data.verifyToken?.payload != nil
                let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .down
                checks.append(ConsoleHealthCheck(
                    id: "core_auth_verify_jwt",
                    section: .core,
                    title: "Auth · JWT verify",
                    tier: tier,
                    detail: ok ? "verifyToken OK · \(ms) ms" : "empty",
                    latencyMs: ms,
                    requestSummary: "mutation verifyToken(token: <access>)",
                    responseSummary: ok ? "payload present" : "nil",
                    timeline: ["verifyToken"],
                    lastMessageAt: nil,
                    reconnectAttempts: 0,
                    deliverySuccessRate: nil
                ))
            } catch {
                checks.append(ConsoleHealthCheck(id: "core_auth_verify_jwt", section: .core, title: "Auth · JWT verify", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation verifyToken", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            }
        } else {
            checks.append(ConsoleHealthCheck(id: "core_auth_verify_jwt", section: .core, title: "Auth · JWT verify", tier: .skipped, detail: "No access token on client.", latencyMs: 0, requestSummary: "mutation verifyToken", responseSummary: "—", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        return checks
    }

    // MARK: Messaging

    private static func probeMessagingSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_msg_inbox", section: .core, title: "Messaging · inbox", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_msg_roundtrip", section: .core, title: "Messaging · send + persistence", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        let chat = ChatService()
        chat.updateAuthToken(graphQL.debugPeekAuthToken())

        var checks: [ConsoleHealthCheck] = []

        let tInbox = CFAbsoluteTimeGetCurrent()
        do {
            let convs = try await chat.getConversations()
            let ms = Int((CFAbsoluteTimeGetCurrent() - tInbox) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            checks.append(ConsoleHealthCheck(
                id: "core_msg_inbox",
                section: .core,
                title: "Messaging · inbox",
                tier: tier,
                detail: "conversations · \(convs.count) threads · \(ms) ms",
                latencyMs: ms,
                requestSummary: "query Conversations",
                responseSummary: "count=\(convs.count)",
                timeline: ["getConversations"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))

            // Never send a probe message into `conversations.first`: that is almost always a buyer/seller thread and
            // would deliver a real message + push to the other party. Inbox read is enough for health here.
            checks.append(ConsoleHealthCheck(
                id: "core_msg_roundtrip",
                section: .core,
                title: "Messaging · send + persistence",
                tier: .skipped,
                detail: "Send probe disabled — posting would notify the other participant. Use WebSocket / inbox checks only.",
                latencyMs: 0,
                requestSummary: "—",
                responseSummary: "skipped",
                timeline: [],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_msg_inbox", section: .core, title: "Messaging · inbox", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "query Conversations", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            checks.append(ConsoleHealthCheck(id: "core_msg_roundtrip", section: .core, title: "Messaging · send + persistence", tier: .skipped, detail: "Skipped (inbox failed)", latencyMs: 0, requestSummary: "—", responseSummary: "—", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        return checks
    }

    // MARK: Listings

    private static func probeListingsSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_list_fetch", section: .core, title: "Listings · fetch (staff)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_list_create", section: .core, title: "Listings · create (probe)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_list_delete", section: .core, title: "Listings · delete (probe)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_list_publish_metric", section: .core, title: "Listings · publish latency est.", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        var checks: [ConsoleHealthCheck] = []

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let page = try await PreluraAdminAPI.allProductsPage(client: graphQL, page: 1, pageSize: 5, statusFilter: nil)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            checks.append(ConsoleHealthCheck(
                id: "core_list_fetch",
                section: .core,
                title: "Listings · fetch (staff)",
                tier: tier,
                detail: "allProducts ACTIVE slice · \(page.rows.count) rows · \(ms) ms",
                latencyMs: ms,
                requestSummary: "query Products (staff)",
                responseSummary: "rows=\(page.rows.count)",
                timeline: ["allProducts"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))

            // Create probe: invalid category → should fail without creating a listing
            do {
                let q = """
                mutation HealthCreateProduct($category: Int!, $name: String!, $description: String!, $price: Float!, $imageUrl: [ImagesInputType]!) {
                  createProduct(category: $category, name: $name, description: $description, price: $price, imagesUrl: $imageUrl) {
                    success message
                  }
                }
                """
                struct Env: Decodable { let createProduct: CP? }
                struct CP: Decodable { let success: Bool?; let message: String? }
                let t1 = CFAbsoluteTimeGetCurrent()
                let data = try await graphQL.execute(
                    query: q,
                    variables: [
                        "category": 0,
                        "name": "health",
                        "description": "probe",
                        "price": 1.0,
                        "imageUrl": [["url": "https://example.invalid/x", "thumbnail": "https://example.invalid/t"]],
                    ],
                    operationName: "HealthCreateProduct",
                    responseType: Env.self
                )
                let ms1 = Int((CFAbsoluteTimeGetCurrent() - t1) * 1000)
                let pathOk = data.createProduct?.success != true
                let tier1: ConsoleHealthTier = pathOk ? (ms1 >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
                checks.append(ConsoleHealthCheck(
                    id: "core_list_create",
                    section: .core,
                    title: "Listings · create (probe)",
                    tier: tier1,
                    detail: pathOk ? "mutation reachable (rejected) · \(ms1) ms — \(data.createProduct?.message ?? "")" : "Unexpected success",
                    latencyMs: ms1,
                    requestSummary: "mutation HealthCreateProduct(invalid category)",
                    responseSummary: data.createProduct?.message ?? "",
                    timeline: ["createProduct"],
                    lastMessageAt: nil,
                    reconnectAttempts: 0,
                    deliverySuccessRate: nil
                ))
            } catch {
                checks.append(ConsoleHealthCheck(id: "core_list_create", section: .core, title: "Listings · create (probe)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation HealthCreateProduct", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            }

            // Delete probe: non-owned id
            do {
                let q = """
                mutation HealthDeleteProduct($productId: Int!) {
                  deleteProduct(productId: $productId) { success message }
                }
                """
                struct Env: Decodable { let deleteProduct: DP? }
                struct DP: Decodable { let success: Bool?; let message: String? }
                let t2 = CFAbsoluteTimeGetCurrent()
                let data = try await graphQL.execute(query: q, variables: ["productId": 0], operationName: "HealthDeleteProduct", responseType: Env.self)
                let ms2 = Int((CFAbsoluteTimeGetCurrent() - t2) * 1000)
                let pathOk = data.deleteProduct?.success != true
                let tier2: ConsoleHealthTier = pathOk ? (ms2 >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
                checks.append(ConsoleHealthCheck(
                    id: "core_list_delete",
                    section: .core,
                    title: "Listings · delete (probe)",
                    tier: tier2,
                    detail: pathOk ? "mutation reachable · \(ms2) ms — \(data.deleteProduct?.message ?? "")" : "Unexpected success",
                    latencyMs: ms2,
                    requestSummary: "mutation deleteProduct(productId: 0)",
                    responseSummary: data.deleteProduct?.message ?? "",
                    timeline: ["deleteProduct"],
                    lastMessageAt: nil,
                    reconnectAttempts: 0,
                    deliverySuccessRate: nil
                ))
            } catch {
                checks.append(ConsoleHealthCheck(id: "core_list_delete", section: .core, title: "Listings · delete (probe)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation deleteProduct", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            }

            let publishDetail = "Uses staff allProducts latency as coarse signal (full publish includes uploads)."
            checks.append(ConsoleHealthCheck(
                id: "core_list_publish_metric",
                section: .core,
                title: "Listings · publish latency est.",
                tier: tier,
                detail: "\(publishDetail) Sample \(ms) ms",
                latencyMs: ms,
                requestSummary: "query allProducts page=1 count=5",
                responseSummary: "see fetch row",
                timeline: ["derived"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_list_fetch", section: .core, title: "Listings · fetch (staff)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "query Products", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        return checks
    }

    // MARK: Payments

    private static func probePaymentsSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_pay_intent", section: .core, title: "Payments · intent", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_pay_confirm", section: .core, title: "Payments · confirm", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_pay_webhook", section: .core, title: "Payments · webhooks", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_pay_last_ok", section: .core, title: "Payments · last success (heuristic)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_pay_failed_detect", section: .core, title: "Payments · failed detection", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        var checks: [ConsoleHealthCheck] = []

        // Intent: invalid order + pm → resolver should fail cleanly
        do {
            let q = """
            mutation HealthCPI($orderId: Int!, $paymentMethodId: String!) {
              createPaymentIntent(orderId: $orderId, paymentMethodId: $paymentMethodId) {
                clientSecret
                paymentRef
              }
            }
            """
            struct Env: Decodable { let createPaymentIntent: CPI? }
            struct CPI: Decodable { let clientSecret: String?; let paymentRef: String? }
            let t0 = CFAbsoluteTimeGetCurrent()
            let (data, errs) = try await graphQL.executeAllowingGraphQLErrors(
                query: q,
                variables: ["orderId": 0, "paymentMethodId": "pm_health_invalid"],
                operationName: "HealthCPI",
                responseType: Env.self
            )
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let empty = data?.createPaymentIntent?.clientSecret == nil && data?.createPaymentIntent?.paymentRef == nil
            let path = empty || !(errs ?? []).isEmpty
            let tier: ConsoleHealthTier = path ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
            let msg = [(errs ?? []).map(\.message).joined(separator: " | "), data?.createPaymentIntent?.paymentRef ?? ""].joined(separator: " ")
            checks.append(ConsoleHealthCheck(
                id: "core_pay_intent",
                section: .core,
                title: "Payments · intent",
                tier: tier,
                detail: path ? "createPaymentIntent path OK · \(ms) ms" : "Unexpected payload",
                latencyMs: ms,
                requestSummary: "mutation createPaymentIntent(orderId: 0, …)",
                responseSummary: String(msg.prefix(400)),
                timeline: ["createPaymentIntent"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_pay_intent", section: .core, title: "Payments · intent", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation createPaymentIntent", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        checks.append(ConsoleHealthCheck(
            id: "core_pay_confirm",
            section: .core,
            title: "Payments · confirm",
            tier: .skipped,
            detail: "Needs Stripe clientSecret from a real checkout — not run from Console.",
            latencyMs: 0,
            requestSummary: "Stripe SDK confirmPayment",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        checks.append(ConsoleHealthCheck(
            id: "core_pay_webhook",
            section: .core,
            title: "Payments · webhooks",
            tier: .skipped,
            detail: "Stripe webhooks are server-side — check Voltis dashboard / logs.",
            latencyMs: 0,
            requestSummary: "POST /stripe/webhook/ (server)",
            responseSummary: "N/A client-side",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        // Last successful payment heuristic: newest COMPLETED-ish admin order
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let orders = try await PreluraAdminAPI.adminOrdersPage(client: graphQL, page: 1, pageSize: 15)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let done = orders.rows.first { ($0.status ?? "").uppercased().contains("COMPLET") || ($0.status ?? "").uppercased().contains("DELIVER") }
            let tier: ConsoleHealthTier = orders.rows.isEmpty ? .degraded : (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy)
            let detail: String
            if let d = done?.createdAt, let u = done?.user?.username {
                detail = "Latest settled sample @\(u) · \(d) · admin list \(ms) ms"
            } else if let first = orders.rows.first {
                detail = "No completed-like row in first page; latest status=\(first.status ?? "?") · \(ms) ms"
            } else {
                detail = "No orders in admin slice — \(ms) ms"
            }
            checks.append(ConsoleHealthCheck(
                id: "core_pay_last_ok",
                section: .core,
                title: "Payments · last success (heuristic)",
                tier: tier,
                detail: detail,
                latencyMs: ms,
                requestSummary: "query adminAllOrders",
                responseSummary: "rows=\(orders.rows.count)",
                timeline: ["adminAllOrders"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_pay_last_ok", section: .core, title: "Payments · last success (heuristic)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "adminAllOrders", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        checks.append(ConsoleHealthCheck(
            id: "core_pay_failed_detect",
            section: .core,
            title: "Payments · failed detection",
            tier: .skipped,
            detail: "Observe cancelled / failed rows in admin orders or Stripe; no silent client signal.",
            latencyMs: 0,
            requestSummary: "—",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        return checks
    }

    // MARK: Push

    private static func probePushSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_push_send", section: .core, title: "Push · send (debug)", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_push_token", section: .core, title: "Push · device token", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        var checks: [ConsoleHealthCheck] = []

        let q = """
        mutation HealthSendPush {
          sendDebugTestPush { success message }
        }
        """
        struct Env: Decodable { let sendDebugTestPush: SP? }
        struct SP: Decodable { let success: Bool?; let message: String? }
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let data = try await graphQL.execute(query: q, operationName: "HealthSendPush", responseType: Env.self)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let ok = data.sendDebugTestPush?.success == true
            let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy) : .degraded
            if ok {
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "myprelura.console.lastPushOkAt")
            }
            let last = UserDefaults.standard.double(forKey: "myprelura.console.lastPushOkAt")
            let lastStr = last > 0 ? Date(timeIntervalSince1970: last).formatted(date: .abbreviated, time: .standard) : "never"
            checks.append(ConsoleHealthCheck(
                id: "core_push_send",
                section: .core,
                title: "Push · send (debug)",
                tier: tier,
                detail: "\(data.sendDebugTestPush?.message ?? "") · \(ms) ms · last OK logged: \(lastStr)",
                latencyMs: ms,
                requestSummary: "mutation sendDebugTestPush",
                responseSummary: "success=\(data.sendDebugTestPush?.success ?? false)",
                timeline: ["sendDebugTestPush"],
                lastMessageAt: ok ? Date() : nil,
                reconnectAttempts: 0,
                deliverySuccessRate: ok ? 1.0 : 0.0
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_push_send", section: .core, title: "Push · send (debug)", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "mutation sendDebugTestPush", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        let tokenPresent = !(UserDefaults.standard.string(forKey: kDeviceTokenKey) ?? "").isEmpty
        checks.append(ConsoleHealthCheck(
            id: "core_push_token",
            section: .core,
            title: "Push · device token (local)",
            tier: tokenPresent ? .healthy : .degraded,
            detail: tokenPresent ? "FCM token present in UserDefaults on device." : "No device token — open shopper build once or wait for registration.",
            latencyMs: 0,
            requestSummary: "UserDefaults \(kDeviceTokenKey)",
            responseSummary: tokenPresent ? "present" : "missing",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        checks.append(ConsoleHealthCheck(
            id: "core_push_delivery",
            section: .core,
            title: "Push · delivery confirm",
            tier: .skipped,
            detail: "APNs/FCM delivery requires device notification center; use debug push + physical device.",
            latencyMs: 0,
            requestSummary: "OS-level",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        return checks
    }

    // MARK: Search

    private static func probeSearchSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_search_q", section: .core, title: "Search · query", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_search_empty", section: .core, title: "Search · empty guard", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        let ps = ProductService()
        ps.updateAuthTokenIfAvailable()

        var checks: [ConsoleHealthCheck] = []

        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let items = try await ps.searchProducts(query: "a", pageNumber: 1, pageCount: 12)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.searchSlowMs ? .degraded : .healthy
            let acc = items.isEmpty ? "0 results (may be normal)" : "\(items.count) results"
            checks.append(ConsoleHealthCheck(
                id: "core_search_q",
                section: .core,
                title: "Search · query",
                tier: items.isEmpty ? .degraded : tier,
                detail: "getAllProducts search · \(ms) ms · \(acc)",
                latencyMs: ms,
                requestSummary: "query getAllProducts(search: \"a\")",
                responseSummary: "count=\(items.count)",
                timeline: ["search"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_search_q", section: .core, title: "Search · query", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "search", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        let t1 = CFAbsoluteTimeGetCurrent()
        do {
            let empty = try await ps.searchProducts(query: "   ", pageNumber: 1, pageCount: 5)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t1) * 1000)
            checks.append(ConsoleHealthCheck(
                id: "core_search_empty",
                section: .core,
                title: "Search · empty guard",
                tier: .healthy,
                detail: "Whitespace query handled · \(empty.count) rows · \(ms) ms",
                latencyMs: ms,
                requestSummary: "search \"   \"",
                responseSummary: "count=\(empty.count)",
                timeline: ["search-empty"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_search_empty", section: .core, title: "Search · empty guard", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "search empty", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        return checks
    }

    // MARK: Media

    private static func probeMediaSuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_media_upload", section: .core, title: "Media · upload endpoint", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_media_image", section: .core, title: "Media · listing image fetch", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }

        var checks: [ConsoleHealthCheck] = []

        guard let u = URL(string: Constants.graphQLUploadURL) else {
            checks.append(ConsoleHealthCheck(id: "core_media_upload", section: .core, title: "Media · upload endpoint", tier: .down, detail: "Bad URL", latencyMs: 0, requestSummary: "", responseSummary: "", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            return checks
        }
        var req = URLRequest(url: u)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 8
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = (200 ... 499).contains(code) // 405/401 still proves route exists
            let tier: ConsoleHealthTier = ok ? (ms >= HealthThresholds.httpSlowMs ? .degraded : .healthy) : .down
            checks.append(ConsoleHealthCheck(
                id: "core_media_upload",
                section: .core,
                title: "Media · upload endpoint",
                tier: tier,
                detail: "HEAD graphql/uploads · \(ms) ms · HTTP \(code)",
                latencyMs: ms,
                requestSummary: "HEAD \(u.absoluteString)",
                responseSummary: "status=\(code)",
                timeline: [],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_media_upload", section: .core, title: "Media · upload endpoint", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "HEAD uploads", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Sample first listing image GET
        do {
            let page = try await PreluraAdminAPI.allProductsPage(client: graphQL, page: 1, pageSize: 1, statusFilter: nil)
            if let raw = page.rows.first?.imagesUrl.first,
               let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) {
                var r = URLRequest(url: url)
                r.httpMethod = "GET"
                r.timeoutInterval = 12
                let t1 = CFAbsoluteTimeGetCurrent()
                let (_, resp) = try await URLSession.shared.data(for: r)
                let ms = Int((CFAbsoluteTimeGetCurrent() - t1) * 1000)
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let ok = (200 ... 299).contains(code)
                let tier: ConsoleHealthTier = ok ? (ms >= 1_200 ? .degraded : .healthy) : .down
                checks.append(ConsoleHealthCheck(
                    id: "core_media_image",
                    section: .core,
                    title: "Media · listing image fetch",
                    tier: tier,
                    detail: ok ? "GET image · \(ms) ms · HTTP \(code)" : "HTTP \(code)",
                    latencyMs: ms,
                    requestSummary: "GET \(url.absoluteString.prefix(120))…",
                    responseSummary: "status=\(code)",
                    timeline: [],
                    lastMessageAt: nil,
                    reconnectAttempts: 0,
                    deliverySuccessRate: nil
                ))
            } else {
                checks.append(ConsoleHealthCheck(id: "core_media_image", section: .core, title: "Media · listing image fetch", tier: .skipped, detail: "No image URL in first listing.", latencyMs: 0, requestSummary: "GET product image", responseSummary: "—", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
            }
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_media_image", section: .core, title: "Media · listing image fetch", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "GET image", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        checks.append(ConsoleHealthCheck(
            id: "core_media_bg_remove",
            section: .core,
            title: "Media · background removal",
            tier: .skipped,
            detail: "Not used in this client build — no GraphQL probe.",
            latencyMs: 0,
            requestSummary: "—",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        return checks
    }

    // MARK: AI

    private static func probeAISuite(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "core_ai_rec", section: .core, title: "AI · recommendations", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_ai_mod", section: .core, title: "AI · moderation", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "core_ai_price", section: .core, title: "AI · pricing hints", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }
        var checks: [ConsoleHealthCheck] = []

        do {
            let q = """
            query HealthRecommend($pageCount: Int!, $pageNumber: Int!) {
              recommendProducts(pageCount: $pageCount, pageNumber: $pageNumber) {
                id name
              }
            }
            """
            struct Env: Decodable { let recommendProducts: [RP]? }
            struct RP: Decodable { let id: Int?; let name: String? }
            let t0 = CFAbsoluteTimeGetCurrent()
            let data = try await graphQL.execute(query: q, variables: ["pageCount": 5, "pageNumber": 1], operationName: "HealthRecommend", responseType: Env.self)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let c = data.recommendProducts?.count ?? 0
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs ? .degraded : .healthy
            checks.append(ConsoleHealthCheck(
                id: "core_ai_rec",
                section: .core,
                title: "AI · recommendations",
                tier: c == 0 ? .degraded : tier,
                detail: "recommendProducts · \(c) rows · \(ms) ms",
                latencyMs: ms,
                requestSummary: "query recommendProducts",
                responseSummary: "count=\(c)",
                timeline: ["recommendProducts"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            checks.append(ConsoleHealthCheck(id: "core_ai_rec", section: .core, title: "AI · recommendations", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "recommendProducts", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        checks.append(ConsoleHealthCheck(
            id: "core_ai_mod",
            section: .core,
            title: "AI · moderation",
            tier: .skipped,
            detail: "No dedicated moderation GraphQL in schema — use reports queue + manual review.",
            latencyMs: 0,
            requestSummary: "—",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        checks.append(ConsoleHealthCheck(
            id: "core_ai_price",
            section: .core,
            title: "AI · pricing hints",
            tier: .skipped,
            detail: "No pricing-AI field exposed — skipped.",
            latencyMs: 0,
            requestSummary: "—",
            responseSummary: "N/A",
            timeline: [],
            lastMessageAt: nil,
            reconnectAttempts: 0,
            deliverySuccessRate: nil
        ))

        return checks
    }

    // MARK: User flows

    private static func probeUserFlows(graphQL: GraphQLClient, sim: Bool) async -> [ConsoleHealthCheck] {
        if sim {
            return [
                ConsoleHealthCheck(id: "flow_buy", section: .flows, title: "Flow · buy path", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "flow_sell", section: .flows, title: "Flow · sell path", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
                ConsoleHealthCheck(id: "flow_chat", section: .flows, title: "Flow · chat path", tier: .down, detail: "Simulated down.", latencyMs: 0, requestSummary: "—", responseSummary: "(simulated)", timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil),
            ]
        }

        var flowChecks: [ConsoleHealthCheck] = []

        // Buy: search + price filter
        let ps = ProductService()
        ps.updateAuthTokenIfAvailable()
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let s = try await ps.searchProducts(query: "dress", pageNumber: 1, pageCount: 8)
            let p = try await ps.filterProductsByPrice(priceLimit: 9_999, pageNumber: 1, pageCount: 8)
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs * 2 ? .degraded : .healthy
            flowChecks.append(ConsoleHealthCheck(
                id: "flow_buy",
                section: .flows,
                title: "Flow · buy path",
                tier: tier,
                detail: "search(\(s.count)) + filterByPrice(\(p.count)) · \(ms) ms total",
                latencyMs: ms,
                requestSummary: "getAllProducts(search) → filterProductsByPrice",
                responseSummary: "ok",
                timeline: ["search", "price"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            flowChecks.append(ConsoleHealthCheck(id: "flow_buy", section: .flows, title: "Flow · buy path", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "buy flow", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Sell: staff listings + create probe (reuse listings suite logic condensed)
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            _ = try await PreluraAdminAPI.allProductsPage(client: graphQL, page: 1, pageSize: 3, statusFilter: nil)
            let q = """
            mutation FlowSellProbe($category: Int!, $name: String!, $description: String!, $price: Float!, $imageUrl: [ImagesInputType]!) {
              createProduct(category: $category, name: $name, description: $description, price: $price, imagesUrl: $imageUrl) { success message }
            }
            """
            struct Env: Decodable { let createProduct: CP? }
            struct CP: Decodable { let success: Bool?; let message: String? }
            _ = try await graphQL.execute(
                query: q,
                variables: [
                    "category": -1,
                    "name": "flow",
                    "description": "probe",
                    "price": 2.0,
                    "imageUrl": [["url": "https://example.invalid/a", "thumbnail": "https://example.invalid/b"]],
                ],
                operationName: "FlowSellProbe",
                responseType: Env.self
            )
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            flowChecks.append(ConsoleHealthCheck(
                id: "flow_sell",
                section: .flows,
                title: "Flow · sell path",
                tier: ms >= HealthThresholds.gqlSlowMs * 2 ? .degraded : .healthy,
                detail: "browse staff feed + createProduct guard · \(ms) ms",
                latencyMs: ms,
                requestSummary: "allProducts + createProduct(invalid)",
                responseSummary: "sequential OK",
                timeline: ["list", "create"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            flowChecks.append(ConsoleHealthCheck(id: "flow_sell", section: .flows, title: "Flow · sell path", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "sell flow", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        // Chat flow: inbox read only — never sendMessage into arbitrary threads (notifies the other party).
        let chat = ChatService()
        chat.updateAuthToken(graphQL.debugPeekAuthToken())
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            let convs = try await chat.getConversations()
            let ms = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
            let tier: ConsoleHealthTier = ms >= HealthThresholds.gqlSlowMs * 2 ? .degraded : .healthy
            flowChecks.append(ConsoleHealthCheck(
                id: "flow_chat",
                section: .flows,
                title: "Flow · chat path",
                tier: tier,
                detail: "inbox \(convs.count) threads · \(ms) ms · send probe omitted (user-visible)",
                latencyMs: ms,
                requestSummary: "query Conversations",
                responseSummary: "threads=\(convs.count)",
                timeline: ["inbox"],
                lastMessageAt: nil,
                reconnectAttempts: 0,
                deliverySuccessRate: nil
            ))
        } catch {
            flowChecks.append(ConsoleHealthCheck(id: "flow_chat", section: .flows, title: "Flow · chat path", tier: .down, detail: error.localizedDescription, latencyMs: 0, requestSummary: "chat flow", responseSummary: String(describing: error), timeline: [], lastMessageAt: nil, reconnectAttempts: 0, deliverySuccessRate: nil))
        }

        return flowChecks
    }
}

// MARK: - GraphQLClient token peek (debug only for health)

extension GraphQLClient {
    /// Non-persistent read of the Bearer token for verifyToken / WS probes (never log this string).
    func debugPeekAuthToken() -> String? {
        UserDefaults.standard.string(forKey: "AUTH_TOKEN")?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }
}

extension ProductService {
    fileprivate func updateAuthTokenIfAvailable() {
        updateAuthToken(UserDefaults.standard.string(forKey: "AUTH_TOKEN"))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - WebSocket handshake probe

private enum WebSocketHandshakeProbe {
    struct Result {
        var connected: Bool
        var openMs: Int
        var firstFrameMs: Int?
        var framesReceived: Int
        var silentConnected: Bool
        var reconnects: Int
        var lastFrameAt: Date?
        var timeline: [String]
    }

    static func probeConversationsChannel(token: String, waitForFrameSeconds: Double) async -> Result {
        await withCheckedContinuation { continuation in
            final class Box: NSObject, URLSessionWebSocketDelegate, @unchecked Sendable {
                var openStart: CFAbsoluteTime = 0
                var openedAt: CFAbsoluteTime?
                var firstFrameAt: CFAbsoluteTime?
                var frames = 0
                var reconnects = 0
                var timeline: [String] = []
                var session: URLSession?
                var task: URLSessionWebSocketTask?
                private var done = false
                private let doneLock = NSLock()
                let waitSec: Double
                let resume: (Result) -> Void

                init(waitSec: Double, resume: @escaping (Result) -> Void) {
                    self.waitSec = waitSec
                    self.resume = resume
                }

                func finish(_ r: Result) {
                    doneLock.lock()
                    guard !done else {
                        doneLock.unlock()
                        return
                    }
                    done = true
                    doneLock.unlock()
                    task?.cancel(with: .goingAway, reason: nil)
                    session?.invalidateAndCancel()
                    resume(r)
                }

                func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
                    openedAt = CFAbsoluteTimeGetCurrent()
                    timeline.append("didOpen")
                    Task { await receiveLoop() }
                }

                func receiveLoop() async {
                    guard let task else { return }
                    let deadline = Date().addingTimeInterval(waitSec)
                    var shouldFinalize = true
                    while Date() < deadline {
                        doneLock.lock()
                        let cancelled = done
                        doneLock.unlock()
                        if cancelled { shouldFinalize = false; break }
                        do {
                            let msg = try await task.receive()
                            if firstFrameAt == nil { firstFrameAt = CFAbsoluteTimeGetCurrent() }
                            frames += 1
                            switch msg {
                            case .string, .data:
                                break
                            @unknown default:
                                break
                            }
                        } catch {
                            timeline.append("recv_err: \(error.localizedDescription)")
                            break
                        }
                    }
                    if shouldFinalize { emitFinal() }
                }

                func emitFinal() {
                    let openMs: Int
                    if let o = openedAt {
                        openMs = Int((o - openStart) * 1000)
                    } else {
                        openMs = 10_000
                    }
                    let firstMs: Int?
                    if let o = openedAt, let f = firstFrameAt {
                        firstMs = Int((f - o) * 1000)
                    } else {
                        firstMs = nil
                    }
                    let connected = openedAt != nil
                    let silent = connected && frames == 0
                    let lastAt: Date? = firstFrameAt.map { Date(timeIntervalSinceReferenceDate: $0) }
                    finish(Result(
                        connected: connected,
                        openMs: min(openMs, 60_000),
                        firstFrameMs: firstMs,
                        framesReceived: frames,
                        silentConnected: silent,
                        reconnects: reconnects,
                        lastFrameAt: lastAt,
                        timeline: timeline
                    ))
                }

                func applyTimeoutIfNeeded() {
                    doneLock.lock()
                    let already = done
                    doneLock.unlock()
                    if !already {
                        timeline.append("probe_timeout")
                        emitFinal()
                    }
                }
            }

            guard let url = URL(string: Constants.conversationsWebSocketURL) else {
                continuation.resume(returning: Result(connected: false, openMs: 0, firstFrameMs: nil, framesReceived: 0, silentConnected: false, reconnects: 0, lastFrameAt: nil, timeline: ["bad url"]))
                return
            }

            let box = Box(waitSec: waitForFrameSeconds) { continuation.resume(returning: $0) }
            var req = URLRequest(url: url)
            req.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = waitForFrameSeconds + 2
            let sess = URLSession(configuration: cfg, delegate: box, delegateQueue: nil)
            box.session = sess
            box.openStart = CFAbsoluteTimeGetCurrent()
            let task = sess.webSocketTask(with: req)
            box.task = task
            task.resume()

            DispatchQueue.global().asyncAfter(deadline: .now() + waitForFrameSeconds + 1.0) {
                box.applyTimeoutIfNeeded()
            }
        }
    }
}
