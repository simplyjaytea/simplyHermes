import Foundation

/// Lets one action run at a time. A second start while the first is still running is refused.
///
/// The composer uses it so a double tap on Send saves the message once: the draft clears only after the save, so a
/// second tap would otherwise save the same text again (review M5).
public struct SingleFlight: Sendable, Equatable {
    private var running = false

    public init() {}

    /// Starts the action. Returns false, and changes nothing, while an earlier start has not ended.
    public mutating func begin() -> Bool {
        guard !running else { return false }
        running = true
        return true
    }

    /// Ends the action, so the next start is accepted.
    public mutating func end() {
        running = false
    }
}
