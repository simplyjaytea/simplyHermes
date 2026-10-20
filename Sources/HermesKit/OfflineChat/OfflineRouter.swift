import Foundation

/// How far the app can reach the Hermes server, as offline chat sees it. Built from the connection's phase
/// (``ConnectionPhase``), so there is no second network probe.
public enum ServerReachability: Sendable, Equatable {
    /// The WebSocket is open.
    case reachable
    /// No news yet: starting up, signing in or trying again. This is neither a recovery nor an outage.
    case unknown
    /// The server did not answer: the socket dropped and keeps retrying, or the last attempt did not get through.
    case unreachable
    /// The server answered but the user has to act (sign in, update, trust a key). That is not an outage.
    case needsAttention

    /// Sorts a connection phase.
    public init(_ phase: ConnectionPhase) {
        switch phase {
        case .connected:
            self = .reachable
        case .idle, .unlocking, .openingTunnel, .checkingServer, .connecting:
            self = .unknown
        case .reconnecting:
            self = .unreachable
        case .signInRequired, .updateRequired:
            self = .needsAttention
        case .failed(let failure):
            self = Self.sort(failure)
        }
    }

    /// A failed attempt is an outage when the server gave no usable answer. Anything the user has to fix (address,
    /// sign-in, host key, an old server) is not.
    private static func sort(_ failure: ConnectionTestFailure) -> ServerReachability {
        switch failure {
        case .unreachable, .webSocket, .server, .ssh: .unreachable
        default: .needsAttention
        }
    }
}

/// Where a new message goes.
public enum OfflineRoute: Sendable, Equatable {
    /// To Hermes on the server. The normal case.
    case server
    /// To the on-device model, in the offline chat ("Offline, no Hermes tools").
    case offline
    /// The server is out of reach and the on-device model cannot answer, for this reason.
    case unavailable(LocalModelUnavailable)
}

/// Decides where a new message goes when the server may be out of reach (plan Q44).
///
/// Messages go offline only after the server has stayed unreachable for ``grace`` seconds, so a brief drop does not
/// flap the chat between Hermes and the on-device model. They return to the server as soon as it is reachable.
/// A start-up or retry step (``ServerReachability/unknown``) neither starts nor ends an outage.
///
/// The router is a value. ``observe(_:at:)`` takes the latest connection state; then
/// ``route(onDeviceEnabled:availability:at:)`` is a pure function of that state, the Settings switch and the
/// model's availability. Times are seconds on a monotonic clock (``GatewayClock/now()``), so a changed system date
/// cannot hold a chat offline.
public struct OfflineRouter: Sendable, Equatable {
    /// Seconds the server must stay unreachable before messages go to the on-device model.
    public static let defaultGrace = 3.0

    /// Seconds of unreachable time that make an outage.
    public let grace: Double
    /// When the server was first found unreachable in the current outage. Nil when it is reachable or no outage began.
    public private(set) var unreachableSince: Double?

    /// Creates a router with no outage.
    public init(grace: Double = OfflineRouter.defaultGrace) {
        self.grace = grace
    }

    /// Feeds the latest reachability. Reachable (or a state that needs the user) ends the outage; unreachable starts
    /// one if none is running; unknown changes nothing.
    public mutating func observe(_ reachability: ServerReachability, at now: Double) {
        switch reachability {
        case .reachable, .needsAttention:
            unreachableSince = nil
        case .unreachable:
            if unreachableSince == nil { unreachableSince = now }
        case .unknown:
            break
        }
    }

    /// Feeds the latest connection phase.
    public mutating func observe(_ phase: ConnectionPhase, at now: Double) {
        observe(ServerReachability(phase), at: now)
    }

    /// When messages start going offline if the server stays unreachable. Nil when no outage is running.
    public var offlineAt: Double? { unreachableSince.map { $0 + grace } }

    /// True once the server has been unreachable for the whole grace period.
    public func isOutage(at now: Double) -> Bool {
        offlineAt.map { now >= $0 } ?? false
    }

    /// Where a message written at `now` goes. `onDeviceEnabled` is the Settings switch (``OnDeviceSettings``) and
    /// `availability` what the on-device model reports. With the server reachable (or inside the grace period) the
    /// answer is always ``OfflineRoute/server``; the other two settings only matter in an outage.
    public func route(onDeviceEnabled: Bool, availability: LocalModelAvailability, at now: Double) -> OfflineRoute {
        guard isOutage(at: now) else { return .server }
        guard onDeviceEnabled else { return .unavailable(.switchedOff) }
        switch availability {
        case .available: return .offline
        case .unavailable(let reason): return .unavailable(reason)
        }
    }
}
