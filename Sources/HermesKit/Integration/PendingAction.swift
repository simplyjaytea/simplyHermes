import Foundation

/// Something the app should do the moment it becomes active, left by an intent or control that ran outside it.
///
/// "Open Quick Entry" from the Action button or Control Center uses this: the intent records the action, iOS brings
/// the app forward, and the app presents the sheet when it sees the action. When the intent already ran inside the
/// app it presents the sheet directly and no file is needed.
public struct PendingAction: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case quickEntry
    }

    public static let fileName = "pending-action.json"
    /// An action nobody picked up in this time is stale and ignored: opening Quick Entry minutes later would surprise.
    public static let timeToLive: TimeInterval = 120

    public var kind: Kind
    /// Text for the Quick Entry field, if the request carried some.
    public var prefill: String?
    public var createdAt: Date

    public init(kind: Kind, prefill: String? = nil, createdAt: Date) {
        self.kind = kind
        self.prefill = prefill
        self.createdAt = createdAt
    }

    public func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(createdAt)
        return age >= 0 && age <= Self.timeToLive
    }
}

/// Reads and writes the pending action file in the shared container.
public struct PendingActionStore: Sendable {
    private let store: JSONFileStore<PendingAction>

    public init(directory: URL) {
        store = JSONFileStore(directory: directory, fileName: PendingAction.fileName)
    }

    /// Records an action, replacing any older one.
    public func post(_ action: PendingAction) throws {
        try store.save(action)
    }

    /// Takes the action out of the file. Returns it only when it is still fresh, so each action runs once.
    public func consume(now: Date) -> PendingAction? {
        guard let action = store.load() else { return nil }
        store.remove()
        return action.isFresh(at: now) ? action : nil
    }
}
