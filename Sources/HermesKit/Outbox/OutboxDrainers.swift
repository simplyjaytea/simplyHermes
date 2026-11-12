import Foundation

/// One ``OutboxDrainer`` per chat for the whole process, however many chat models come and go.
///
/// A chat model is rebuilt when the user switches servers and back, or opens the chat in a second window. A rebuilt
/// model with a drainer of its own would run ``OutboxDrainer/recoverInterrupted()`` on its first attach and move a
/// message that is still in flight on the old model back to `pending`, so it would go out twice. The registry hands
/// every model of a chat the same drainer, and says when the drainer is new: only then is recovery due, because only
/// then can nothing be in flight. That is once per chat per launch, which is what recovery is for.
public final class OutboxDrainers: @unchecked Sendable {
    private let lock = NSLock()
    private var drainers: [String: OutboxDrainer] = [:]

    public init() {}

    /// The chat's drainer, made by `make` the first time this chat asks. `isNew` is true only for that first call.
    public func drainer(
        forChat chatID: String, make: () -> OutboxDrainer
    ) -> (drainer: OutboxDrainer, isNew: Bool) {
        lock.withLock {
            if let existing = drainers[chatID] { return (existing, false) }
            let drainer = make()
            drainers[chatID] = drainer
            return (drainer, true)
        }
    }
}
