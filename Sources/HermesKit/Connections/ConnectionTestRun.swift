import Foundation

/// Tracks one press of a connection form's Test button, so an answer from an older or edited form cannot change
/// the current one.
///
/// A connection test can take seconds, while the form stays editable. Each run records the form values it was
/// started with. A run's progress and result count only while it is still the current run and its recorded values
/// still match the form. Anything else is stale and must be discarded.
public struct ConnectionTestRunTracker<Target: Equatable & Sendable>: Sendable {
    /// One test run: its identity and the form values it was started with.
    public struct Run: Sendable, Equatable {
        /// Increases with each run, so a newer run can be told from an older one with the same target.
        public let id: UInt64
        /// The captured form values, such as the address and secrets the test uses.
        public let target: Target

        /// Creates a run.
        public init(id: UInt64, target: Target) {
            self.id = id
            self.target = target
        }
    }

    private var nextID: UInt64 = 0
    /// The run whose progress and result may still change the form. Nil after the run ends or is discarded.
    public private(set) var current: Run?

    /// Creates an empty tracker.
    public init() {}

    /// Starts a run for `target` and makes it the current one. Any older run becomes stale.
    @discardableResult
    public mutating func begin(_ target: Target) -> Run {
        nextID += 1
        let run = Run(id: nextID, target: target)
        current = run
        return run
    }

    /// True while `run` is the current run. A newer run supersedes it.
    public func isCurrent(_ run: Run) -> Bool { current == run }

    /// True while `run` is current and the form still has the values it was started with.
    public func isCurrent(_ run: Run, target: Target) -> Bool {
        current == run && run.target == target
    }

    /// Ends `run` when it is still current, so a late progress update can't arrive after its result.
    public mutating func finish(_ run: Run) {
        if current?.id == run.id { current = nil }
    }

    /// Ends the current run, for example when the form's inputs change. Older runs stay stale.
    public mutating func invalidate() {
        current = nil
    }
}
