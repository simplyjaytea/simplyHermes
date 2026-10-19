import Foundation

/// An open SSH tunnel: where the dashboard answers, its per-process token, and how to stop it.
public struct OpenedTunnel: Sendable {
    /// The local forwarded endpoint.
    public var endpoint: HermesEndpoint
    /// The dashboard's session token (REST header and `?token=` on the WebSocket).
    public var sessionToken: String
    /// Stops this tunnel. Called once.
    public var close: @Sendable () async -> Void

    /// Creates a value.
    public init(endpoint: HermesEndpoint, sessionToken: String, close: @escaping @Sendable () async -> Void) {
        self.endpoint = endpoint
        self.sessionToken = sessionToken
        self.close = close
    }
}

/// A server that passed the HTTP check: everything needed to open the WebSocket and call REST.
public struct CheckedServer: Sendable {
    /// What the check found.
    public var summary: ServerSummary
    /// The endpoint the WebSocket uses.
    public var endpoint: HermesEndpoint
    /// The signed-in REST client.
    public var rest: RESTClient
    /// Credentials for each WebSocket connect.
    public var credentials: GatewayCredentialProvider

    /// Creates a value.
    public init(
        summary: ServerSummary, endpoint: HermesEndpoint, rest: RESTClient,
        credentials: @escaping GatewayCredentialProvider
    ) {
        self.summary = summary
        self.endpoint = endpoint
        self.rest = rest
        self.credentials = credentials
    }
}

/// The side effects ``ConnectionManager`` needs. The app's driver reads the Keychain, runs SSH and signs in; tests
/// pass a fake. Throw ``ConnectionTestFailure`` for errors the user can act on.
public protocol ConnectionDriver: Sendable {
    /// Asks for Face ID or the passcode.
    func unlock(_ connection: ServerConnection) async -> Bool
    /// SSH only: logs in, starts Hermes and opens the tunnel. The manager calls the tunnel's `close` when done.
    func openTunnel(_ connection: ServerConnection) async throws -> OpenedTunnel
    /// Reads health and status, signs in, and checks compatibility.
    func checkServer(_ connection: ServerConnection, tunnel: OpenedTunnel?) async throws -> CheckedServer
    /// The WebSocket transport for a connection.
    func webSocketTransport(for connection: ServerConnection) -> any WebSocketTransport
}

/// Why ``ConnectionManager/client(for:)`` could not hand out a client.
public struct ConnectionUnavailable: Error, Sendable, Equatable {
    /// The phase the connection stopped in.
    public var phase: ConnectionPhase

    /// Creates a value.
    public init(phase: ConnectionPhase) {
        self.phase = phase
    }
}

/// Saved connections at run time (WP-15): connects on demand, one ``GatewayClient`` per connection, and the
/// lifecycle of each (``ConnectionLifecycle``).
public actor ConnectionManager {
    private struct Live {
        var connection: ServerConnection
        var lifecycle: ConnectionLifecycle
        /// Bumped on every connect and stop, so late results from an earlier attempt are dropped.
        var generation = 0
        var tunnel: OpenedTunnel?
        var checked: CheckedServer?
        var client: GatewayClient?
        var listener: Task<Void, Never>?
        var waiters: [CheckedContinuation<GatewayClient, any Error>] = []
    }

    private let driver: any ConnectionDriver
    private let clientConfig: GatewayClientConfig
    private let clock: any GatewayClock
    private let onConnected: @Sendable (UUID) -> Void
    private var live: [UUID: Live] = [:]
    private var profiles: [UUID: String] = [:]
    private var observers: [UUID: AsyncStream<ConnectionPhaseChange>.Continuation] = [:]

    /// Creates a manager. `onConnected` runs after each successful first connect (record "last used").
    public init(
        driver: any ConnectionDriver, clientConfig: GatewayClientConfig = GatewayClientConfig(),
        clock: any GatewayClock = SystemGatewayClock(), onConnected: @escaping @Sendable (UUID) -> Void = { _ in }
    ) {
        self.driver = driver
        self.clientConfig = clientConfig
        self.clock = clock
        self.onConnected = onConnected
    }

    // MARK: - Public API

    /// The phase of a connection. Idle when the manager has not seen it.
    public func phase(of id: UUID) -> ConnectionPhase {
        live[id]?.lifecycle.phase ?? .idle
    }

    /// Phase changes of every connection, from now on.
    public func phaseChanges() -> AsyncStream<ConnectionPhaseChange> {
        let (stream, continuation) = AsyncStream<ConnectionPhaseChange>.makeStream()
        let key = UUID()
        observers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(key) }
        }
        return stream
    }

    /// Starts connecting when the connection is not connected or connecting. Returns at once.
    public func connect(_ connection: ServerConnection) {
        var entry = live[connection.id] ?? Live(connection: connection, lifecycle: ConnectionLifecycle(for: connection))
        if entry.lifecycle.phase.acceptsConnect {
            // Pick up edits (address, sign-in, Face ID) made since the last connect.
            entry.connection = connection
            entry.lifecycle = ConnectionLifecycle(for: connection)
        }
        live[connection.id] = entry
        apply(.connectRequested, to: connection.id)
    }

    /// The connected client, connecting first when needed (connect on demand). Throws ``ConnectionUnavailable``
    /// when the connection stops short: Face ID refused, sign-in needed, server too old, or a failure.
    public func client(for connection: ServerConnection) async throws -> GatewayClient {
        if case .connected = phase(of: connection.id), let client = live[connection.id]?.client { return client }
        connect(connection)
        if case .connected = phase(of: connection.id), let client = live[connection.id]?.client { return client }
        let id = connection.id
        return try await withCheckedThrowingContinuation { continuation in
            if let phase = live[id]?.lifecycle.phase, !phase.isBusy {
                continuation.resume(throwing: ConnectionUnavailable(phase: phase))
            } else {
                live[id]?.waiters.append(continuation)
            }
        }
    }

    /// Sets the active profile of a connection. Its REST calls and every gateway method that takes `profile` carry it
    /// (nil follows the server's active profile). It applies to the live clients now and to every later reconnect.
    public func setProfile(_ name: String?, for id: UUID) {
        profiles[id] = name
        guard let entry = live[id] else { return }
        let rest = entry.checked?.rest
        let client = entry.client
        Task {
            await rest?.setProfile(name)
            await client?.setProfile(name)
        }
    }

    /// The active profile of a connection, if one was chosen.
    public func profile(of id: UUID) -> String? { profiles[id] }

    /// The signed-in REST client of a connected (or reconnecting) connection.
    public func rest(for id: UUID) -> RESTClient? {
        live[id]?.checked?.rest
    }

    /// A terminal connector for a connection, connecting first when needed. It uses the endpoint and credentials
    /// that the chat socket uses.
    public func terminalConnector(
        for connection: ServerConnection, transport: any TerminalSocketTransport
    ) async throws -> TerminalConnector {
        _ = try await client(for: connection)
        guard let checked = live[connection.id]?.checked else {
            throw ConnectionUnavailable(phase: phase(of: connection.id))
        }
        return TerminalConnector(endpoint: checked.endpoint, credentials: checked.credentials, transport: transport)
    }

    /// Feeds `info.desktop_contract` from a session result into the compatibility check.
    public func reportSessionInfo(_ info: SessionInfo?, for id: UUID) {
        apply(.contractReported(info?.desktopContract), to: id)
    }

    /// Disconnects. The connection goes back to idle and connects again on demand.
    public func disconnect(_ id: UUID) {
        apply(.disconnectRequested, to: id)
    }

    /// Disconnects and forgets a connection (deleted, or edited so it must start over).
    public func remove(_ id: UUID) {
        apply(.disconnectRequested, to: id)
        live[id] = nil
        profiles[id] = nil
    }

    // MARK: - State machine

    private func apply(_ event: ConnectionLifecycleEvent, to id: UUID) {
        guard var entry = live[id] else { return }
        let before = entry.lifecycle.phase
        let effects = entry.lifecycle.handle(event)
        if (event == .connectRequested && !effects.isEmpty) || event == .disconnectRequested { entry.generation += 1 }
        live[id] = entry
        for effect in effects { run(effect, for: id) }
        let after = live[id]?.lifecycle.phase ?? .idle
        if after != before {
            for observer in observers.values { observer.yield(ConnectionPhaseChange(id: id, phase: after)) }
        }
        resolveWaiters(id)
    }

    /// Applies an event from async work, unless the attempt it belongs to is over.
    private func complete(_ event: ConnectionLifecycleEvent, for id: UUID, generation: Int) {
        guard live[id]?.generation == generation else { return }
        apply(event, to: id)
    }

    private func run(_ effect: ConnectionEffect, for id: UUID) {
        guard let entry = live[id] else { return }
        let connection = entry.connection
        let generation = entry.generation
        let driver = driver
        switch effect {
        case .unlock:
            Task {
                let granted = await driver.unlock(connection)
                self.complete(.unlocked(granted), for: id, generation: generation)
            }
        case .openTunnel:
            Task {
                do {
                    let tunnel = try await driver.openTunnel(connection)
                    self.tunnelOpened(tunnel, for: id, generation: generation)
                } catch {
                    self.complete(.failed(Self.failure(error)), for: id, generation: generation)
                }
            }
        case .checkServer:
            let tunnel = entry.tunnel
            Task {
                do {
                    let checked = try await driver.checkServer(connection, tunnel: tunnel)
                    self.serverChecked(checked, for: id, generation: generation)
                } catch {
                    self.complete(.failed(Self.failure(error)), for: id, generation: generation)
                }
            }
        case .startSocket:
            startSocket(for: id)
        case .stopSocket:
            stopSocket(for: id)
        case .closeTunnel:
            guard let tunnel = entry.tunnel else { return }
            live[id]?.tunnel = nil
            Task { await tunnel.close() }
        case .recordConnected:
            onConnected(id)
        }
    }

    private func tunnelOpened(_ tunnel: OpenedTunnel, for id: UUID, generation: Int) {
        guard live[id]?.generation == generation, live[id]?.lifecycle.phase == .openingTunnel else {
            // The attempt ended while the tunnel was opening.
            Task { await tunnel.close() }
            return
        }
        live[id]?.tunnel = tunnel
        apply(.tunnelOpened, to: id)
    }

    private func serverChecked(_ checked: CheckedServer, for id: UUID, generation: Int) {
        guard live[id]?.generation == generation else { return }
        live[id]?.checked = checked
        apply(.serverChecked(checked.summary), to: id)
    }

    private func startSocket(for id: UUID) {
        guard let entry = live[id], let checked = entry.checked else { return }
        let client = GatewayClient(
            endpoint: checked.endpoint, transport: driver.webSocketTransport(for: entry.connection),
            credentials: checked.credentials, clock: clock, config: clientConfig)
        let generation = entry.generation
        let profile = profiles[id]
        live[id]?.client = client
        live[id]?.listener = Task {
            let events = await client.events()
            // Scope both clients before the socket opens, so nothing is sent unscoped once connected.
            await client.setProfile(profile)
            await checked.rest.setProfile(profile)
            await client.start()
            for await event in events {
                guard case .state(let state) = event else { continue }
                self.complete(.socket(state), for: id, generation: generation)
            }
        }
    }

    private func stopSocket(for id: UUID) {
        guard let client = live[id]?.client else { return }
        live[id]?.listener?.cancel()
        live[id]?.listener = nil
        live[id]?.client = nil
        live[id]?.checked = nil
        Task { await client.stop() }
    }

    private func resolveWaiters(_ id: UUID) {
        guard let entry = live[id], !entry.waiters.isEmpty else { return }
        let phase = entry.lifecycle.phase
        if case .connected = phase, let client = entry.client {
            live[id]?.waiters = []
            for waiter in entry.waiters { waiter.resume(returning: client) }
        } else if !phase.isBusy {
            live[id]?.waiters = []
            for waiter in entry.waiters { waiter.resume(throwing: ConnectionUnavailable(phase: phase)) }
        }
    }

    private func removeObserver(_ key: UUID) {
        observers[key] = nil
    }

    static func failure(_ error: any Error) -> ConnectionTestFailure {
        switch error {
        case let failure as ConnectionTestFailure: failure
        case is GatewaySignInRequired: .signInRequired(providers: [])
        default: GatewayConnectionTester.reachFailure(error)
        }
    }
}

/// One phase change from ``ConnectionManager/phaseChanges()``.
public struct ConnectionPhaseChange: Sendable, Equatable {
    /// The connection.
    public var id: UUID
    /// Its new phase.
    public var phase: ConnectionPhase
}
