import Foundation

/// Chats whose outbox must not send right now. A chat waiting out its Undo window after Delete is paused, so a
/// message that is still waiting doesn't go to a chat the user is deleting. Resuming lets the next drain send it.
///
/// Pauses live in memory only: a pending delete doesn't survive a relaunch, so neither does its pause.
public final class OutboxPauses: @unchecked Sendable {
    /// The app's registry. Every ``OutboxDrainer`` reads it unless a test passes its own.
    public static let shared = OutboxPauses()

    private let lock = NSLock()
    private var paused: Set<String> = []

    public init() {}

    public func pause(_ chatID: String) {
        lock.withLock { _ = paused.insert(chatID) }
    }

    public func resume(_ chatID: String) {
        lock.withLock { _ = paused.remove(chatID) }
    }

    public func isPaused(_ chatID: String) -> Bool {
        lock.withLock { paused.contains(chatID) }
    }
}
