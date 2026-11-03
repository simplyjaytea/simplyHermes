import Foundation

/// When a chat's waiting messages are sent again (WP-8). Pure, so every transition has a table row in the tests.
public enum OutboxResume {
    /// True when the chat has just come back: its pill moved into `.connected` from any other state. A chat that was
    /// already connected does not drain again, so one reconnect sends the waiting messages once.
    public static func shouldDrain(from previous: PillState?, to next: PillState) -> Bool {
        next == .connected && previous != .connected
    }
}
