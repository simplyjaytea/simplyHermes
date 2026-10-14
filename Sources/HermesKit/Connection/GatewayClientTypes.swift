import Foundation

/// What the client puts on the WebSocket URL.
public enum GatewayCredential: Sendable, Equatable {
    /// Gateway mode: a single-use ticket from `POST /api/auth/ws-ticket` (`?ticket=`).
    case ticket(String)
    /// SSH mode: the per-process session token (`?token=`).
    case token(String)
    /// No credential.
    case none
}

/// Why the client asks for a credential. Gateway mode needs a fresh single-use ticket for every connect.
public enum GatewayCredentialRequest: Sendable, Equatable {
    /// First connect, or a reconnect after a network drop.
    case initial
    /// The server answered 403 to the upgrade: mint a new ticket.
    case afterRejection
    /// A fresh ticket was also rejected: sign in again, then mint a ticket.
    case reauthenticate
}

/// Thrown by a credential provider when the user must sign in again by hand. The client stops with
/// ``GatewayFailure/signInRequired``. Any other error from the provider is treated as transient and retried.
public struct GatewaySignInRequired: Error, Sendable {
    /// Creates the error.
    public init() {}
}

/// Supplies the credential for each connect.
public typealias GatewayCredentialProvider = @Sendable (GatewayCredentialRequest) async throws -> GatewayCredential

/// Why the client gave up.
public enum GatewayFailure: Sendable, Equatable {
    /// The server rejected the upgrade even with a fresh ticket after a new sign-in.
    case authenticationRejected
    /// The credential provider reported that the user must sign in again.
    case signInRequired
}

/// Where the connection is in its life.
public enum GatewayConnectionState: Sendable, Equatable {
    /// Not started.
    case idle
    /// Opening the socket (attempt 0 is the first).
    case connecting(attempt: Int)
    /// The socket is open and the handshake (`gateway.ready`, `client.capabilities`) is done.
    case connected
    /// Waiting `delay` seconds before the next attempt.
    case waitingToReconnect(attempt: Int, delay: Double)
    /// Stopped for a reason only the user can fix. Call ``GatewayClient/start()`` after signing in.
    case failed(GatewayFailure)
    /// Stopped by ``GatewayClient/stop()``.
    case stopped
}

/// Tuning knobs. Defaults match `docs/protocol.md`.
public struct GatewayClientConfig: Sendable {
    /// Seconds to wait for the socket to open and for `gateway.ready`.
    public var connectTimeout: Double = 15
    /// Default request timeout in seconds.
    public var requestTimeout: Double = 120
    /// Timeout for `approval.respond` in seconds (matches the server's approval window).
    public var approvalRespondTimeout: Double = 300
    /// Seconds between `gateway.ping` frames when the server asked for heartbeats.
    public var heartbeatInterval: Double = 15
    /// Seconds of inbound silence after which the socket is dropped.
    public var silenceDeadline: Double = 45
    /// Reconnect backoff.
    public var reconnect = ReconnectPolicy()
    /// The WebSocket path.
    public var path = "/api/ws"

    /// Creates the default configuration.
    public init() {}
}

/// Errors from ``GatewayClient`` calls.
public enum GatewayClientError: Error, Sendable, Equatable {
    /// There is no open, handshaken connection.
    case notConnected
    /// The connection closed while the request was waiting.
    case disconnected
    /// No response arrived in time.
    case timedOut(method: String)
    /// The client was stopped.
    case stopped
}

/// How a session came back after a reconnect.
public enum GatewaySessionReattach: Sendable, Equatable {
    /// The live session was still on the server (inside the 20 s grace). Missed events were replayed.
    case live
    /// The live session was gone, so it was rebuilt from storage with `session.resume`. The reducer must start
    /// from the result (transcript plus `inflight`) and the live id changed.
    case cold
}

/// What the client tells its owner.
public enum GatewayClientEvent: Sendable, Equatable {
    /// The connection state changed.
    case state(GatewayConnectionState)
    /// `gateway.ready` arrived.
    case ready(GatewayReadyEvent)
    /// A gateway event. `replayed` is true when it came from `session.events.since` after a reconnect.
    case event(GatewayEventEnvelope, replayed: Bool)
    /// A tracked session is attached again after a reconnect.
    case sessionReattached(oldLiveID: String, result: SessionAttachResult, how: GatewaySessionReattach)
    /// The replay ring overflowed, so the gap cannot be shown. Re-read the history. The watermark is now `latestSeq`.
    case replayTruncated(sessionID: String, latestSeq: Int)
    /// A server request that was still unanswered before the drop, re-delivered by `session.events.since`.
    /// Answer approvals with `approval.respond`: a plain JSON-RPC response only works on the socket that got the request.
    case openRequestReplayed(sessionID: String, request: OpenRequestEntry)
    /// The server process restarted (`replay_epoch` changed). All sessions are rebuilt cold.
    case serverRestarted
    /// Another connection took the session over, or the server reclaimed it. Show "Continued on another device".
    case sessionReclaimed(liveID: String, storedID: String?, reason: String?)
    /// Re-attaching a tracked session failed.
    case resyncFailed(sessionID: String, message: String)
}

/// Answers one server-to-client request. Return the JSON-RPC `result`. Throwing answers `-32603`.
public typealias GatewayServerRequestHandler = @Sendable (RPCRequest) async throws -> JSONValue
