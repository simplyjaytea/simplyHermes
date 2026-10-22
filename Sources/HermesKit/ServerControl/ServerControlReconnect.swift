import Foundation

/// How the wait for the server to answer again ended.
public enum ServerControlReconnectOutcome: Sendable, Equatable {
    /// The server answered on this probe (1 is the first).
    case reachable(probes: Int)
    /// No probe succeeded within the window.
    case timedOut(probes: Int)
}

/// The "Reconnecting…" wait after a stop or restart: probe until the server answers, for up to ``window`` seconds
/// (60 by plan). Every wait goes through the ``GatewayClock``, so tests run in virtual time.
public struct ServerControlReconnect: Sendable, Equatable {
    /// The plan's window: 60 seconds.
    public static let defaultWindow: Double = 60
    /// Seconds between probes: 2.
    public static let defaultInterval: Double = 2

    /// Longest wait from the action to the last probe, in seconds.
    public var window: Double
    /// Seconds between probes.
    public var interval: Double
    /// Seconds to wait before the first probe, so a restart has time to take the server down.
    public var settle: Double

    /// Creates the wait. The defaults are the plan's: 60 s window, probes every 2 s, no settle.
    public init(
        window: Double = ServerControlReconnect.defaultWindow,
        interval: Double = ServerControlReconnect.defaultInterval,
        settle: Double = 0
    ) {
        self.window = window
        self.interval = interval
        self.settle = settle
    }

    /// Probes until one succeeds or the window ends. The window starts before the settle wait.
    public func run(
        clock: any GatewayClock, probe: @Sendable () async -> Bool
    ) async throws -> ServerControlReconnectOutcome {
        let start = clock.now()
        if settle > 0 { try await clock.sleep(seconds: settle) }
        var probes = 0
        while true {
            probes += 1
            if await probe() { return .reachable(probes: probes) }
            let elapsed = clock.now() - start
            if elapsed >= window { return .timedOut(probes: probes) }
            try await clock.sleep(seconds: min(interval, window - elapsed))
        }
    }
}
