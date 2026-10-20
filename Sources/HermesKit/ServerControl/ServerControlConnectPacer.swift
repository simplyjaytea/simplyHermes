import Foundation

/// Paces the reconnects of one server-control action. A poll that finds the connection down may start a connect,
/// but not on every probe: an SSH connect asks for Face ID, and a repeated prompt every few seconds is a bug. Over
/// SSH the pacer also has a budget, so a long wait ends in a few prompts at most (WP-54).
public actor ServerControlConnectPacer {
    /// Seconds between connects: 15.
    public static let defaultSpacing: Duration = .seconds(15)

    private let spacing: Duration
    private let budget: Int?
    private var last: ContinuousClock.Instant?
    private var used = 0

    /// Creates a pacer. `budget` caps the connects it allows; nil means no cap.
    public init(spacing: Duration = ServerControlConnectPacer.defaultSpacing, budget: Int? = nil) {
        self.spacing = spacing
        self.budget = budget
    }

    /// True when a connect may start at `now`, and records it. The first call is always allowed, unless the budget is
    /// spent.
    public func mayConnect(at now: ContinuousClock.Instant = ContinuousClock.now) -> Bool {
        if let budget, used >= budget { return false }
        if let last, now - last < spacing { return false }
        last = now
        used += 1
        return true
    }
}
