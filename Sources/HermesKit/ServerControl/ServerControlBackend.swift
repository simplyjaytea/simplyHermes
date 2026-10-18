import Foundation

/// What one gateway action came to.
public enum ServerControlActionOutcome: Sendable, Equatable {
    /// The server took the action. Start and drain do not wait.
    case sent
    /// Stop or restart, and the server answered again after this many probes.
    case reconnected(probes: Int)
    /// Stop or restart, and the server did not answer within the window.
    case timedOut(probes: Int)
}

/// Reaches one saved server for the server-control screens (WP-54).
///
/// ``rest()`` connects on demand and waits for the connection, for the first call of an action. The polls use
/// ``liveRest()``, which never waits: a server that stays down must not hang a poll. It also paces its reconnects,
/// because an SSH connect asks for Face ID.
public struct ServerControlBackend: Sendable {
    /// The saved connection this backend reaches.
    public let connection: ServerConnection
    private let manager: ConnectionManager
    /// Shared by every copy of this backend, so one action's polls share one pace.
    private let pacer: ServerControlConnectPacer

    /// Creates a backend for `connection`.
    public init(manager: ConnectionManager, connection: ServerConnection) {
        self.manager = manager
        self.connection = connection
        // Over SSH each reconnect may ask for Face ID, so one action gets a few attempts. A gateway connect is silent.
        self.pacer = ServerControlConnectPacer(budget: connection.isSSH ? 4 : nil)
    }

    /// True for SSH connections, which restart through the connection manager.
    public var isSSH: Bool { connection.isSSH }

    /// The signed-in REST client. Connects first when needed.
    public func rest() async throws -> RESTClient {
        _ = try await manager.client(for: connection)
        guard let rest = await manager.rest(for: connection.id) else { throw ServerControlError.notConnected }
        return rest
    }

    /// The REST client when the connection is up now, or nil. Never connects.
    public func connectedRest() async -> RESTClient? {
        await manager.rest(for: connection.id)
    }

    /// The REST client when the connection is up now. Otherwise starts a connect, at most once per
    /// ``ServerControlConnectPacer`` pace, and returns nil.
    public func liveRest() async -> RESTClient? {
        if let rest = await manager.rest(for: connection.id) { return rest }
        if await pacer.mayConnect() { await manager.connect(connection) }
        return nil
    }

    /// Sends a gateway action. Stop and restart then wait for the server to answer again, for up to 60 s. Over SSH a
    /// restart also drops the connection, so the manager starts a new tunnel and the dashboard before the wait.
    public func perform(
        _ action: ServerControlAction, clock: any GatewayClock
    ) async throws -> ServerControlActionOutcome {
        let rest = try await rest()
        try await rest.gatewayControl(action)
        guard action.waitsForServer else { return .sent }
        if action == .restart && isSSH { await manager.disconnect(connection.id) }
        let outcome = try await awaitServer(clock: clock, settle: action == .restart ? 2 : 0)
        switch outcome {
        case .reachable(let probes): return .reconnected(probes: probes)
        case .timedOut(let probes): return .timedOut(probes: probes)
        }
    }

    /// Probes `/api/status` until the server answers, for up to 60 s.
    public func awaitServer(clock: any GatewayClock, settle: Double = 0) async throws -> ServerControlReconnectOutcome {
        let backend = self
        return try await ServerControlReconnect(settle: settle).run(clock: clock) {
            guard let rest = await backend.liveRest() else { return false }
            return (try? await rest.controlStatus()) != nil
        }
    }

    /// One receipt read for a poll. Never waits on a connection; a failed read is ``HermesUpdatePoll/unreachable``.
    public func pollReceipt() async -> HermesUpdatePoll {
        guard let rest = await liveRest() else { return .unreachable }
        do {
            guard let receipt = try await rest.hermesUpdateReceipt() else { return .absent }
            return .receipt(receipt)
        } catch {
            return .unreachable
        }
    }

    /// The update steps for this server, over this connection.
    public func updateSteps() -> HermesUpdateSteps {
        let backend = self
        return HermesUpdateSteps(
            check: { force in try await backend.rest().hermesUpdateCheck(force: force) },
            poll: { await backend.pollReceipt() },
            startUpdate: { try await backend.rest().hermesUpdate() },
            status: {
                guard let rest = await backend.liveRest() else { throw ServerControlError.notConnected }
                return try await rest.controlStatus().server
            })
    }
}
