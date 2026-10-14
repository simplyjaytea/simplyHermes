import Foundation

/// Time source for the gateway client. Tests replace it so heartbeats and backoff run without waiting.
public protocol GatewayClock: Sendable {
    /// Seconds on a monotonic scale. Only differences are meaningful.
    func now() -> Double
    /// Suspends for `seconds`. Throws `CancellationError` when the task is cancelled.
    func sleep(seconds: Double) async throws
}

/// The real clock.
public struct SystemGatewayClock: GatewayClock {
    private let origin = ContinuousClock.now

    /// Creates the system clock.
    public init() {}

    /// Seconds since the clock was created.
    public func now() -> Double {
        let elapsed = origin.duration(to: ContinuousClock.now)
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    /// Sleeps with `Task.sleep`.
    public func sleep(seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }
}

/// Full-jitter exponential backoff: `random(0, min(cap, base * 2^attempt))`.
public struct ReconnectPolicy: Sendable {
    /// Base delay in seconds.
    public var base: Double
    /// Upper bound of the delay in seconds.
    public var cap: Double
    /// A socket that dies sooner than this after opening counts as a failed attempt, so the ladder does not reset.
    public var minStableUptime: Double
    /// Returns a random value in `0...upperBound`. Tests inject a fixed one.
    public var jitter: @Sendable (Double) -> Double

    /// Creates a policy. Defaults are 300 ms base, 15 s cap and 5 s stability.
    public init(
        base: Double = 0.3,
        cap: Double = 15,
        minStableUptime: Double = 5,
        jitter: @escaping @Sendable (Double) -> Double = { Double.random(in: 0...max($0, 0)) }
    ) {
        self.base = base
        self.cap = cap
        self.minStableUptime = minStableUptime
        self.jitter = jitter
    }

    /// The delay before reconnect attempt number `attempt` (0 is the first retry).
    public func delay(attempt: Int) -> Double {
        let exponent = Double(min(max(attempt, 0), 30))
        let upper = min(cap, base * pow(2, exponent))
        return jitter(upper)
    }
}
