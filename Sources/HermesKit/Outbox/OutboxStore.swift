import Foundation

/// Why an outbox operation was refused.
public enum OutboxError: Error, Sendable, Equatable {
    /// The state machine does not allow this move. The stored record is unchanged.
    case illegalTransition(from: DeliveryState, into: DeliveryState)
    /// No record has this id.
    case notFound(UUID)
}

/// Holds outgoing messages until the server acknowledges them, so none is lost to a crash, a relaunch or a dropped
/// connection.
public protocol OutboxStore: Sendable {
    /// Saves a new message. It survives a relaunch.
    func insert(_ record: OutboundRecord) async throws

    /// Moves a message to `state` and returns the updated record. Throws ``OutboxError`` for an unknown id or a move
    /// the state machine does not allow.
    @discardableResult
    func updateState(_ state: DeliveryState, forID id: UUID) async throws -> OutboundRecord

    /// The messages of one chat, oldest first.
    func records(inChat chatID: String) async throws -> [OutboundRecord]

    /// Deletes a chat's acknowledged messages, which the server now has. Returns how many were removed.
    @discardableResult
    func pruneSent(inChat chatID: String) async throws -> Int

    /// Deletes one message the user chose to drop. Other messages are untouched.
    func remove(id: UUID) async throws
}
