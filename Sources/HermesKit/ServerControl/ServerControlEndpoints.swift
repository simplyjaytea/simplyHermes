import Foundation

/// Body of `POST /api/gateway/drain`: `{"action": "drain"}` or `{"action": "cancel"}`. Unverified, needs real server
/// [JT]: the request schema gives this shape, and the testbed recorded no gateway write.
private struct ServerControlDrainBody: Encodable, Sendable {
    var action: String
}

/// The gateway actions the server-control screens send. Stop and restart drop the server for a while.
public enum ServerControlAction: String, Sendable, Equatable, CaseIterable {
    case start
    case stop
    case restart
    case drain
    case cancelDrain

    /// True when the screens wait for the server to answer again: stop and restart.
    public var waitsForServer: Bool { self == .stop || self == .restart }
}

// MARK: - Server control, logs, analytics, stats and updates (WP-54)

extension RESTClient {
    /// `GET /api/status` for the server-control screens. Works without a login. Recorded: GET_api_status.json.
    public func controlStatus() async throws -> ServerControlStatus {
        try await get("/api/status", scoped: false)
    }

    /// `GET /api/system/stats`: host and process figures. Recorded: GET_api_system_stats.json. The OpenAPI does not
    /// type the answer, so it is shown as generic rows.
    public func systemStats() async throws -> JSONValue {
        try await get("/api/system/stats", scoped: false)
    }

    /// `GET /api/health/idle`. Recorded: GET_api_health_idle.json. It is shown as generic rows and is never permission
    /// to retire the server.
    public func healthIdle() async throws -> JSONValue {
        try await get("/api/health/idle", scoped: false)
    }

    /// `GET /api/logs` with the filter's query. Recorded without a query: GET_api_logs.json. The query names are in
    /// docs/protocol/dashboard-openapi.json. No recording sent a query.
    public func serverLogs(_ filter: ServerLogsFilter) async throws -> JSONValue {
        try await get("/api/logs", query: filter.queryItems)
    }

    /// `GET /api/analytics/usage?days=`. Recorded without a query: GET_api_analytics_usage.json (`period_days`). The
    /// `days` name is in docs/protocol/dashboard-openapi.json (1 to 365). No recording sent a query.
    public func analyticsUsage(days: Int) async throws -> JSONValue {
        try await get("/api/analytics/usage", query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// `GET /api/analytics/models?days=`. Recorded without a query: GET_api_analytics_models.json (`period_days`).
    /// The `days` name is in docs/protocol/dashboard-openapi.json (1 to 365). No recording sent a query.
    public func analyticsModels(days: Int) async throws -> JSONValue {
        try await get("/api/analytics/models", query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// Sends a gateway action. Start, stop and restart are `POST /api/gateway/{action}`; drain and cancel drain are
    /// `POST /api/gateway/drain` with an action in the body. Unverified, needs real server [JT]: the recorder forbids
    /// `/api/gateway/*` (Fixtures/rest/index.json), so no answer is recorded. Only the HTTP status is read; the screens
    /// then refetch `GET /api/status`.
    public func gatewayControl(_ action: ServerControlAction) async throws {
        switch action {
        case .start:
            _ = try await sendRaw("POST", "/api/gateway/start")
        case .stop:
            _ = try await sendRaw("POST", "/api/gateway/stop")
        case .restart:
            _ = try await sendRaw("POST", "/api/gateway/restart")
        case .drain, .cancelDrain:
            let body = ServerControlDrainBody(action: action == .cancelDrain ? "cancel" : "drain")
            _ = try await sendRaw("POST", "/api/gateway/drain", body: body, scoped: false)
        }
    }

    /// `GET /api/hermes/update/check?force=`. Recorded without a query: GET_api_hermes_update_check.json. The `force`
    /// name is in docs/protocol/dashboard-openapi.json. No recording sent a query.
    public func hermesUpdateCheck(force: Bool) async throws -> HermesUpdateCheck {
        try await get("/api/hermes/update/check", query: [URLQueryItem(name: "force", value: force ? "true" : "false")])
    }

    /// `POST /api/hermes/update`: starts `hermes update` in the background. Unverified, needs real server [JT]: the
    /// testbed recorded no update write. Only the HTTP status is read; the screens then poll ``hermesUpdateReceipt()``
    /// and `GET /api/status`.
    public func hermesUpdate() async throws {
        _ = try await sendRaw("POST", "/api/hermes/update", scoped: false)
    }

    /// `GET /api/hermes/update/receipt`. The testbed recorded only the 404 answer, `No update receipt found`
    /// (GET_api_hermes_update_receipt.json), so a 404 is nil. The success shape is not recorded: the answer is kept as
    /// JSON and shown as generic rows.
    public func hermesUpdateReceipt() async throws -> JSONValue? {
        do {
            let receipt: JSONValue = try await get("/api/hermes/update/receipt", scoped: false)
            return receipt
        } catch RESTError.http(let status, _) where status == 404 {
            return nil
        }
    }
}
