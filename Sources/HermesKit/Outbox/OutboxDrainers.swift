import Foundation

/// One ``OutboxDrainer`` per chat and server for the whole process, however many chat models come and go.
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

    /// The drainer of chat `chatID` on server `connectionID`, made by `make` the first time it is asked for. `isNew` is
    /// true only for that first call. A chat with the same id on another server gets a drainer of its own.
    public func drainer(
        forChat chatID: String, connection connectionID: String, make: () -> OutboxDrainer
    ) -> (drainer: OutboxDrainer, isNew: Bool) {
        let key = Self.key(chatID, connectionID)
        return lock.withLock {
            if let existing = drainers[key] { return (existing, false) }
            let drainer = make()
            drainers[key] = drainer
            return (drainer, true)
        }
    }

    /// Forgets the drainer of a chat the user deleted, so the registry does not keep one per chat for the whole launch.
    /// Only for a chat that is gone: a model that still held the drainer and attached again would get a new one and
    /// recover messages that are in flight. Returns whether there was one.
    @discardableResult
    public func forget(chat chatID: String, connection connectionID: String) -> Bool {
        lock.withLock { drainers.removeValue(forKey: Self.key(chatID, connectionID)) != nil }
    }

    /// Forgets every drainer of a server that was removed. Returns how many.
    @discardableResult
    public func forgetAll(connection connectionID: String) -> Int {
        lock.withLock {
            let doomed = drainers.keys.filter { $0.hasPrefix("\(connectionID)\u{1F}") }
            for key in doomed { drainers[key] = nil }
            return doomed.count
        }
    }

    private static func key(_ chatID: String, _ connectionID: String) -> String {
        "\(connectionID)\u{1F}\(chatID)"
    }
}
