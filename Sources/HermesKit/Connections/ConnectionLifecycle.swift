/// What the app knows about a server once it is reached (WP-15).
public struct ServerSummary: Sendable, Equatable {
    /// Version for display, such as `git.d97007c`.
    public var serverVersion: String?
    /// `release_date`, such as `2026.9.24`.
    public var releaseDate: String?
    /// The signed-in user, when the server needs a login.
    public var signedInAs: String?
    /// The compatibility verdict.
    public var compatibility: ServerCompatibility

    /// Creates a summary.
    public init(
        serverVersion: String? = nil, releaseDate: String? = nil, signedInAs: String? = nil,
        compatibility: ServerCompatibility = .compatible
    ) {
        self.serverVersion = serverVersion
        self.releaseDate = releaseDate
        self.signedInAs = signedInAs
        self.compatibility = compatibility
    }
}

/// Where one saved connection is. The state diagram is in `docs/architecture.md` ("Connection lifecycle").
public enum ConnectionPhase: Sendable, Equatable {
    /// Not connected. Connects on demand.
    case idle
    /// Waiting for Face ID or the passcode before reading the connection's secrets.
    case unlocking
    /// SSH: logging in, starting Hermes on the server and opening the tunnel.
    case openingTunnel
    /// Reading health and status, signing in, and checking compatibility over HTTP.
    case checkingServer
    /// Opening the WebSocket for the first time.
    case connecting
    /// The WebSocket is open and handshaken.
    case connected(ServerSummary)
    /// The WebSocket dropped; the client retries with backoff. `attempt` counts from 1.
    case reconnecting(attempt: Int)
    /// Only the user can continue: sign in again.
    case signInRequired
    /// The server is too old: show "Update your Hermes". `found` says what was too old.
    case updateRequired(found: String)
    /// The last attempt failed. Connect again to retry.
    case failed(ConnectionTestFailure)

    /// True while work is under way.
    public var isBusy: Bool {
        switch self {
        case .unlocking, .openingTunnel, .checkingServer, .connecting, .reconnecting: true
        case .idle, .connected, .signInRequired, .updateRequired, .failed: false
        }
    }

    /// True when a new connect request starts over: nothing runs and nothing is connected.
    public var acceptsConnect: Bool {
        switch self {
        case .idle, .signInRequired, .updateRequired, .failed: true
        default: false
        }
    }
}

/// What happened to a connection.
public enum ConnectionLifecycleEvent: Sendable, Equatable {
    /// Something needs the connection (connect on demand), or the user tapped Connect or Retry.
    case connectRequested
    /// The Face ID answer.
    case unlocked(Bool)
    /// SSH: the tunnel is open.
    case tunnelOpened
    /// The HTTP check passed.
    case serverChecked(ServerSummary)
    /// The gateway client's state changed.
    case socket(GatewayConnectionState)
    /// A session result carried `info.desktop_contract`.
    case contractReported(JSONValue?)
    /// A step failed.
    case failed(ConnectionTestFailure)
    /// The user disconnected, or the connection was deleted.
    case disconnectRequested
}

/// Work the manager does for a transition.
public enum ConnectionEffect: Sendable, Equatable {
    /// Ask for Face ID.
    case unlock
    /// SSH: open the tunnel.
    case openTunnel
    /// Run the HTTP check.
    case checkServer
    /// Create and start the gateway client.
    case startSocket
    /// Stop the gateway client.
    case stopSocket
    /// SSH: stop the tunnel.
    case closeTunnel
    /// Remember the connection as last used.
    case recordConnected
}

/// The state machine of one connection, without side effects. ``ConnectionManager`` runs the effects.
public struct ConnectionLifecycle: Sendable, Equatable {
    /// The current phase.
    public private(set) var phase: ConnectionPhase = .idle
    /// True for SSH connections: they open a tunnel first and close it when they stop.
    public let isSSH: Bool
    /// True when Face ID comes first.
    public let requiresUnlock: Bool
    private var summary: ServerSummary?

    /// Creates the machine in ``ConnectionPhase/idle``.
    public init(isSSH: Bool, requiresUnlock: Bool) {
        self.isSSH = isSSH
        self.requiresUnlock = requiresUnlock
    }

    /// Creates the machine for a saved connection.
    public init(for connection: ServerConnection) {
        self.init(isSSH: connection.isSSH, requiresUnlock: connection.requiresUnlock)
    }

    /// Applies an event and returns the effects to run, in order. Events that do not fit the phase are ignored.
    public mutating func handle(_ event: ConnectionLifecycleEvent) -> [ConnectionEffect] {
        switch event {
        case .connectRequested:
            guard phase.acceptsConnect else { return [] }
            if requiresUnlock { return move(to: .unlocking, [.unlock]) }
            return startAfterUnlock()
        case .unlocked(let granted):
            guard phase == .unlocking else { return [] }
            return granted ? startAfterUnlock() : move(to: .idle, [])
        case .tunnelOpened:
            guard phase == .openingTunnel else { return [] }
            return move(to: .checkingServer, [.checkServer])
        case .serverChecked(let checked):
            guard phase == .checkingServer else { return [] }
            return serverChecked(checked)
        case .socket(let state):
            return socketChanged(state)
        case .contractReported(let raw):
            return contractReported(raw)
        case .failed(let failure):
            guard phase.isBusy else { return [] }
            return stop(then: Self.phase(for: failure))
        case .disconnectRequested:
            guard phase != .idle else { return [] }
            return stop(then: .idle)
        }
    }

    private mutating func startAfterUnlock() -> [ConnectionEffect] {
        summary = nil
        return isSSH ? move(to: .openingTunnel, [.openTunnel]) : move(to: .checkingServer, [.checkServer])
    }

    private mutating func serverChecked(_ checked: ServerSummary) -> [ConnectionEffect] {
        if case .updateRequired(let found) = checked.compatibility {
            return stop(then: .updateRequired(found: found))
        }
        summary = checked
        return move(to: .connecting, [.startSocket])
    }

    private mutating func socketChanged(_ state: GatewayConnectionState) -> [ConnectionEffect] {
        guard socketRunning else { return [] }
        switch state {
        case .connected:
            let wasFirst = phase == .connecting
            return move(to: .connected(summary ?? ServerSummary()), wasFirst ? [.recordConnected] : [])
        case .connecting(let attempt) where attempt > 0:
            return move(to: .reconnecting(attempt: attempt), [])
        case .waitingToReconnect(let attempt, _):
            return move(to: .reconnecting(attempt: attempt + 1), [])
        case .failed:
            return stop(then: .signInRequired)
        case .idle, .connecting, .stopped:
            return []
        }
    }

    private mutating func contractReported(_ raw: JSONValue?) -> [ConnectionEffect] {
        guard case .connected(var current) = phase else { return [] }
        switch ServerCompatibility.check(desktopContract: raw) {
        case .updateRequired(let found):
            return stop(then: .updateRequired(found: found))
        case .newerThanApp(let contract):
            current.compatibility = .newerThanApp(contract: contract)
            summary = current
            return move(to: .connected(current), [])
        case .compatible:
            return []
        }
    }

    /// True while a gateway client exists.
    private var socketRunning: Bool {
        switch phase {
        case .connecting, .connected, .reconnecting: true
        default: false
        }
    }

    /// Stops what runs in the current phase, then moves to `next`.
    private mutating func stop(then next: ConnectionPhase) -> [ConnectionEffect] {
        var effects: [ConnectionEffect] = []
        if socketRunning { effects.append(.stopSocket) }
        if isSSH && tunnelMayBeOpen { effects.append(.closeTunnel) }
        return move(to: next, effects)
    }

    /// True from the moment the tunnel starts until it is closed.
    private var tunnelMayBeOpen: Bool {
        switch phase {
        case .openingTunnel, .checkingServer, .connecting, .connected, .reconnecting: true
        default: false
        }
    }

    private mutating func move(to next: ConnectionPhase, _ effects: [ConnectionEffect]) -> [ConnectionEffect] {
        phase = next
        return effects
    }

    /// The phase a failure leads to: sign-in problems need the user, everything else can be retried.
    static func phase(for failure: ConnectionTestFailure) -> ConnectionPhase {
        switch failure {
        case .signInRequired, .wrongCredentials, .missingSecret: .signInRequired
        default: .failed(failure)
        }
    }
}
