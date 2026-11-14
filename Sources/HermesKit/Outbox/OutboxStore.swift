import Foundation

/// Why an outbox operation was refused.
public enum OutboxError: Error, Sendable, Equatable {
    /// The state machine does not allow this move. The stored record is unchanged.
    case illegalTransition(from: DeliveryState, into: DeliveryState)
    /// No record has this id.
    case notFound(UUID)
    /// The record is not in the state the caller expected, so the action was not applied. A user's tap raced a send
    /// that already moved the message on.
    case unexpectedState(UUID, actual: DeliveryKind)
}

/// Holds outgoing messages until the server acknowledges them, so none is lost to a crash, a relaunch or a dropped
/// connection.
public protocol OutboxStore: Sendable {
    /// Saves a new message. It survives a relaunch.
    func insert(_ record: OutboundRecord) async throws

    /// Moves a message to `state` and returns the updated record. This is for the outbox's own sends. Throws
    /// ``OutboxError`` for an unknown id or a move the state machine does not allow.
    @discardableResult
    func updateState(_ state: DeliveryState, forID id: UUID) async throws -> OutboundRecord

    /// Moves a message only while it is in the state `current`. Use it for a user's action: a stale tap throws
    /// ``OutboxError/unexpectedState(_:actual:)`` and changes nothing.
    @discardableResult
    func updateState(
        _ state: DeliveryState, forID id: UUID, ifCurrently current: DeliveryKind
    ) async throws -> OutboundRecord

    /// The messages of one chat, oldest first.
    func records(inChat chatID: String) async throws -> [OutboundRecord]

    /// Deletes a chat's acknowledged messages, which the server now has. Returns how many were removed.
    @discardableResult
    func pruneSent(inChat chatID: String) async throws -> Int

    /// Deletes one message only while it is in the state `current`. A message that is being sent cannot be deleted.
    func remove(id: UUID, ifCurrently current: DeliveryKind) async throws

    /// Moves every message of one server's chat to another chat id in one write, keeping their order and states. A New
    /// chat's first message waits under its placeholder id and moves to the server session id once the server made the
    /// chat. `connection` scopes it, so another server's chat with the same id is never touched. Returns how many moved.
    @discardableResult
    func rebind(chat oldID: String, to newID: String, connection: String) async throws -> Int

    /// Deletes every message of one server's chat in one write, for a chat the user deleted. Two servers can reuse a
    /// chat id, so `connection` scopes it: another server's messages are never touched. Returns how many of the
    /// removed messages were waiting (pending or failed), so the app can say how many were discarded.
    @discardableResult
    func removeChat(_ chatID: String, connection: String) async throws -> Int

    /// The chats of one server that hold a message not yet acknowledged (pending, sending or failed), oldest first.
    ///
    /// The server lists a chat only once it holds a message. So a chat whose first message still waits is in nobody's
    /// list after a relaunch or a server switch, and its message would wait with no row to show it. The shell reads
    /// this to put those chats back.
    func unsentChatIDs(connection: String) async throws -> [String]
}

extension OutboxStore {
    /// A store that cannot rebind refuses, so no message is ever moved without being kept. The database store overrides it.
    public func rebind(chat oldID: String, to newID: String, connection: String) async throws -> Int {
        throw OutboxRebindUnsupported()
    }

    /// A store that cannot list them says none. The database store overrides it.
    public func unsentChatIDs(connection: String) async throws -> [String] { [] }

    /// ``unsentChatIDs(connection:)`` without the placeholders: the chats that exist on the server. A placeholder's
    /// row is the New chat queue's to restore.
    public func unsentServerChatIDs(connection: String) async throws -> [String] {
        try await unsentChatIDs(connection: connection).filter { !PlaceholderChat.isPlaceholderID($0) }
    }

    /// How many of one server's chat messages are waiting: pending or failed. A message already sending is not counted,
    /// so the Undo toast never promises to discard a message that is going out.
    public func waitingCount(inChat chatID: String, connection: String) async throws -> Int {
        try await records(inChat: chatID).filter {
            $0.connectionID == connection && ($0.state.kind == .pending || $0.state.kind == .failed)
        }.count
    }
}

/// The store has no atomic rebind.
public struct OutboxRebindUnsupported: Error, Sendable {}
