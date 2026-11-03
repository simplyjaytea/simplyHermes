@preconcurrency import Citadel
import Foundation
import HermesKit
import NIOCore
import NIOSSH

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One saved SSH connection's settings.
public struct SSHConfiguration: Sendable {
    public var host: String
    public var port: Int
    public var username: String
    public var credential: SSHCredential
    public var hostKey: HostKeyPolicy
    /// Custom `hermes` executable, absolute or `~/…`. `nil` searches `PATH`, the login shell and common dirs.
    public var hermesPath: String?
    /// 32 lowercase hex chars, stable per saved connection (``RemoteDashboard/makeOwnershipID()``).
    public var ownershipID: String
    public var readyTimeout: Duration
    public var connectTimeout: Duration

    public init(
        host: String, port: Int = 22, username: String, credential: SSHCredential, hostKey: HostKeyPolicy,
        hermesPath: String? = nil, ownershipID: String, readyTimeout: Duration = RemoteDashboard.defaultReadyTimeout,
        connectTimeout: Duration = .seconds(15)
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.credential = credential
        self.hostKey = hostKey
        self.hermesPath = hermesPath
        self.ownershipID = ownershipID
        self.readyTimeout = readyTimeout
        self.connectTimeout = connectTimeout
    }
}

/// Where the app reaches the dashboard once the tunnel is up. Loopback bind: no login, a session token instead
/// (docs/protocol.md section 2.1).
public struct SSHTunnelEndpoint: Sendable, Equatable {
    /// `http://127.0.0.1:<local port>`.
    public let baseURL: URL
    public let sessionToken: String
    /// The accepted server host key. Store it to pin later connects.
    public let hostKey: HostKeyInfo
    /// What the remote `hermes --version` printed.
    public let hermesVersion: String

    /// The shared transport value (WP-10) for REST and WebSocket clients. Pass ``sessionToken`` alongside it:
    /// `requestHeaders(sessionToken:)` for REST, `webSocketURL(path:token:)` for `/api/ws` (no ticket on loopback).
    public var hermesEndpoint: HermesEndpoint {
        // baseURL is always http://127.0.0.1:<port>, which HermesEndpoint accepts.
        HermesEndpoint(baseURL: baseURL)!
    }

    /// Headers for every REST call.
    public var restHeaders: [String: String] { hermesEndpoint.requestHeaders(sessionToken: sessionToken) }

    /// WebSocket URL with the `?token=` query the loopback server expects (no ticket).
    public func webSocketURL(path: String = "/api/ws") -> URL {
        hermesEndpoint.webSocketURL(path: path, token: sessionToken)
    }
}

/// Progress steps for the connection UI.
public enum SSHTunnelStep: Sendable, Equatable {
    case connecting
    case probing
    case startingDashboard
    case forwarding
    case ready
}

/// SSH mode transport: connect, probe and start the remote dashboard, forward a loopback port, adopt the token.
/// One actor per connection. Call ``stop()`` when the app backgrounds or the user disconnects.
public actor SSHTunnel {
    private let configuration: SSHConfiguration
    private var client: SSHClient?
    private var forwarder: LoopbackForwarder?
    private var remote: (pid: Int32, nonce: String)?
    private var endpoint: SSHTunnelEndpoint?

    public init(configuration: SSHConfiguration) {
        self.configuration = configuration
    }

    /// The current endpoint, if the tunnel is up.
    public var currentEndpoint: SSHTunnelEndpoint? { endpoint }

    /// Brings the tunnel up. Safe to call again while up (returns the same endpoint).
    public func start(progress: (@Sendable (SSHTunnelStep) -> Void)? = nil) async throws -> SSHTunnelEndpoint {
        if let endpoint, client?.isConnected == true { return endpoint }
        await stop()
        do {
            return try await bringUp(progress: progress)
        } catch {
            await stop()
            throw error
        }
    }

    private func bringUp(progress: (@Sendable (SSHTunnelStep) -> Void)?) async throws -> SSHTunnelEndpoint {
        let config = configuration
        progress?(.connecting)
        let validator = HostKeyValidator(policy: config.hostKey)
        let client: SSHClient
        do {
            #if DEBUG
                NetworkTrap.record("ssh")
            #endif
            client = try await SSHClient.connect(
                host: config.host,
                port: config.port,
                authenticationMethod: config.credential.authenticationMethod(username: config.username),
                hostKeyValidator: .custom(validator),
                reconnect: .never,
                connectTimeout: .seconds(config.connectTimeout.components.seconds)
            )
        } catch {
            throw validator.failure ?? error
        }
        self.client = client
        guard let hostKey = validator.accepted else { throw SSHTunnelError.notConnected }

        progress?(.probing)
        let probe = try RemoteDashboard.parseProbe(
            try await run(
                RemoteDashboard.probeCommand(customPath: config.hermesPath), on: client, step: "probe",
                timeout: Self.probeTimeout))
        guard probe.supportsTokenFile else { throw SSHTunnelError.hermesTooOld(version: probe.version) }

        progress?(.startingDashboard)
        let nonce = RemoteDashboard.makeNonce()
        let uploadedToken = RemoteDashboard.makeSessionToken()
        let launch = try RemoteDashboard.launchCommand(
            hermesPath: probe.hermesPath, ownershipID: config.ownershipID, nonce: nonce, token: uploadedToken,
            readyTimeout: config.readyTimeout)
        // The launch script itself waits up to the ready timeout for the dashboard, so its deadline is a little longer.
        let output = try await run(launch, on: client, step: "launch", timeout: config.readyTimeout + Self.launchSlack)
        if let pid = RemoteDashboard.parsePID(output) { remote = (pid, nonce) }
        let remotePort = try RemoteDashboard.parseReady(output)

        progress?(.forwarding)
        let forwarder = try await LoopbackForwarder.start(on: client.eventLoop) { initialize in
            try await client.createDirectTCPIPChannel(
                using: SSHChannelType.DirectTCPIP(
                    targetHost: "127.0.0.1",
                    targetPort: remotePort,
                    originatorAddress: try SocketAddress(ipAddress: "127.0.0.1", port: 0)
                ),
                initialize: initialize
            )
        }
        self.forwarder = forwarder
        let baseURL = URL(string: "http://127.0.0.1:\(forwarder.port)")!
        let token = await Self.adoptServedToken(baseURL: baseURL) ?? uploadedToken

        let endpoint = SSHTunnelEndpoint(
            baseURL: baseURL, sessionToken: token, hostKey: hostKey, hermesVersion: probe.version)
        self.endpoint = endpoint
        progress?(.ready)
        return endpoint
    }

    /// Stops the remote dashboard this tunnel started, the forwarder and the SSH session.
    public func stop() async {
        endpoint = nil
        if let forwarder {
            await forwarder.stop()
            self.forwarder = nil
        }
        if let client {
            let command = remote.flatMap {
                try? RemoteDashboard.stopCommand(ownershipID: configuration.ownershipID, nonce: $0.nonce, pid: $0.pid)
            }
            if let command, client.isConnected {
                _ = try? await run(command, on: client, step: "stop", timeout: Self.stopTimeout)
            }
            try? await client.close()
            self.client = nil
        }
        remote = nil
    }

    /// How long the probe may take: it only reads `hermes --version` and a few paths.
    static let probeTimeout: Duration = .seconds(30)
    /// Extra time the launch gets beyond the dashboard's ready timeout, for the script itself.
    static let launchSlack: Duration = .seconds(30)
    /// How long stopping the remote dashboard may take before the connection is closed anyway.
    static let stopTimeout: Duration = .seconds(15)

    /// Runs a command and returns stdout and stderr together. A non-zero exit is not an error here: the scripts
    /// report failures as marker lines. A command that hasn't finished by `timeout` throws
    /// ``SSHTunnelError/commandTimedOut(step:)``, and the SSH connection is closed so its stream ends.
    private func run(_ command: String, on client: SSHClient, step: String, timeout: Duration) async throws -> String {
        try await Self.withDeadline(
            timeout, step: step, onTimeout: { try? await client.close() },
            body: { try await Self.collect(command, on: client) })
    }

    private static func collect(_ command: String, on client: SSHClient) async throws -> String {
        var output = ByteBuffer()
        do {
            for try await chunk in try await client.executeCommandStream(command) {
                switch chunk {
                case .stdout(var buffer), .stderr(var buffer):
                    output.writeBuffer(&buffer)
                }
            }
        } catch is SSHClient.CommandFailed {
            // Exit status is carried by the markers.
        }
        return String(buffer: output)
    }

    /// Runs `body`, or throws ``SSHTunnelError/commandTimedOut(step:)`` once `timeout` passes, whichever comes first.
    /// The caller is answered at that moment: neither a stuck `body` nor a slow `onTimeout` can hold it up. On timeout,
    /// `body` is cancelled and `onTimeout` (closing the connection, which ends a command stream) starts on its own task,
    /// not awaited. A `body` that finishes first never triggers `onTimeout`, so a command that completes at the deadline
    /// keeps its connection. Whatever `body` throws after a timeout is ignored.
    static func withDeadline<T: Sendable>(
        _ timeout: Duration, step: String, onTimeout: @escaping @Sendable () async -> Void,
        body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let outcome = FirstOutcome<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
                outcome.install(continuation)
                let work = Task {
                    do {
                        outcome.resolve(.success(try await body()))
                    } catch {
                        outcome.resolve(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled,
                        outcome.resolve(.failure(SSHTunnelError.commandTimedOut(step: step)))
                    else { return }
                    work.cancel()
                    Task { await onTimeout() }
                }
                outcome.onSettle {
                    work.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            outcome.resolve(.failure(CancellationError()))
        }
    }

    /// The session for the token fetch: a factory session, so the trap counts it like every other.
    private static let tokenSession = NetworkSessions.make(configuration: .default)

    /// `GET /` through the tunnel and read `window.__HERMES_SESSION_TOKEN__`. Desktop trusts it over its own.
    private static func adoptServedToken(baseURL: URL) async -> String? {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 15
        #if DEBUG
            NetworkTrap.record("http")
        #endif
        guard let (data, _) = try? await tokenSession.data(for: request),
            let html = String(bytes: data, encoding: .utf8)
        else { return nil }
        return RemoteDashboard.parseServedToken(html: html)
    }
}

/// The first result of a deadline race, delivered to the caller exactly once. Later results are dropped.
private final class FirstOutcome<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var early: Result<T, any Error>?
    private var settled = false
    private var cleanup: (@Sendable () -> Void)?

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        let result: Result<T, any Error>? = lock.withLock {
            if let early { return early }
            self.continuation = continuation
            return nil
        }
        if let result { continuation.resume(with: result) }
    }

    /// Runs `cleanup` once the race is settled, or at once if it already is.
    func onSettle(_ cleanup: @escaping @Sendable () -> Void) {
        let runNow = lock.withLock {
            if settled { return true }
            self.cleanup = cleanup
            return false
        }
        if runNow { cleanup() }
    }

    /// Delivers `result` if nothing has been delivered yet. True when this call settled the race.
    @discardableResult
    func resolve(_ result: Result<T, any Error>) -> Bool {
        var waiting: CheckedContinuation<T, any Error>?
        var cleanup: (@Sendable () -> Void)?
        let won: Bool = lock.withLock {
            guard !settled else { return false }
            settled = true
            waiting = continuation
            continuation = nil
            if waiting == nil { early = result }
            cleanup = self.cleanup
            self.cleanup = nil
            return true
        }
        guard won else { return false }
        waiting?.resume(with: result)
        cleanup?()
        return true
    }
}
