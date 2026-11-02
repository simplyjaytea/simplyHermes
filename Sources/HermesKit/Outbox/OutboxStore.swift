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
}
