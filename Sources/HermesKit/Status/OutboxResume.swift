import Foundation

/// When a chat's waiting messages are sent again (WP-8). Pure, so every transition has a table row in the tests.
public enum OutboxResume {
    /// True when the chat has just come back: its pill moved into `.connected` from any other state. A chat that was
    /// already connected does not drain again, so one reconnect sends the waiting messages once.
    public static func shouldDrain(from previous: PillState?, to next: PillState) -> Bool {
        next == .connected && previous != .connected
    }

    /// What a chat does when its pill changes.
    public enum Reaction: Sendable, Equatable {
        /// Nothing: the pill did not move back online, or the chat is retired.
        case nothing
        /// The chat is not attached: attach it, which connects it and sends its waiting messages.
        case attach
        /// The chat is attached: send its waiting messages.
        case drain
    }

    /// The whole decision of a chat's pill watcher. A retired chat (the store dropped it because the active server
    /// changed, board row 108) does nothing: attaching it would connect it to the new server with the old server's
    /// session id. Pure, so every row has a test; the screen model only carries it out.
    public static func reaction(
        from previous: PillState?, to next: PillState, isRetired: Bool, isAttached: Bool
    ) -> Reaction {
        guard !isRetired, shouldDrain(from: previous, to: next) else { return .nothing }
        return isAttached ? .drain : .attach
    }
}
