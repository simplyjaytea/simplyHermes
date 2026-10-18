import Foundation

/// Body of `POST /api/gateway/drain`: `{"action": "drain"}` or `{"action": "cancel"}`.
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
    /// `GET /api/status` for the server-control screens. Works without a login.
    public func controlStatus() async throws -> ServerControlStatus {
        try await get("/api/status", scoped: false)
    }

    /// `GET /api/system/stats`: host and process figures. The OpenAPI does not type the answer.
    public func systemStats() async throws -> JSONValue {
        try await get("/api/system/stats", scoped: false)
    }

    /// `GET /api/health/idle`: a token-gated diagnostic snapshot. It is never permission to retire the server.
    public func healthIdle() async throws -> JSONValue {
        try await get("/api/health/idle", scoped: false)
    }

    /// `GET /api/logs` with the filter's query. The OpenAPI does not type the answer.
    public func serverLogs(_ filter: ServerLogsFilter) async throws -> JSONValue {
        try await get("/api/logs", query: filter.queryItems)
    }

    /// `GET /api/analytics/usage?days=`.
    public func analyticsUsage(days: Int) async throws -> JSONValue {
        try await get("/api/analytics/usage", query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// `GET /api/analytics/models?days=`.
    public func analyticsModels(days: Int) async throws -> JSONValue {
        try await get("/api/analytics/models", query: [URLQueryItem(name: "days", value: String(days))])
    }

    /// Sends a gateway action. Start, stop and restart are `POST /api/gateway/{action}`; drain and cancel drain are
    /// `POST /api/gateway/drain` with an action in the body. The answers are not typed, so only the status counts.
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

    /// `GET /api/hermes/update/check?force=`.
    public func hermesUpdateCheck(force: Bool) async throws -> HermesUpdateCheck {
        try await get("/api/hermes/update/check", query: [URLQueryItem(name: "force", value: force ? "true" : "false")])
    }

    /// `POST /api/hermes/update`: starts `hermes update` in the background. Watch ``hermesUpdateReceipt()`` for the result.
    public func hermesUpdate() async throws {
        _ = try await sendRaw("POST", "/api/hermes/update", scoped: false)
    }

    /// `GET /api/hermes/update/receipt`. Nil when no update has run since receipts began (the server answers 404).
    public func hermesUpdateReceipt() async throws -> JSONValue? {
        do {
            let receipt: JSONValue = try await get("/api/hermes/update/receipt", scoped: false)
            return receipt
        } catch RESTError.http(let status, _) where status == 404 {
            return nil
        }
    }
}
