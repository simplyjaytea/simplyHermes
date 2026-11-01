import Foundation

/// Where an outgoing message is in its delivery. A message is saved as `.pending` before anything is sent.
public enum DeliveryState: Sendable, Equatable, Codable {
    /// Saved and waiting for its chat to take it.
    case pending
    /// Handed to the server, not yet acknowledged.
    case sending
    /// The server acknowledged the message.
    case sent(acknowledgedAt: Date)
    /// Not sent. The reason is shown to the user, who can retry.
    case failed(reason: String)

    /// Whether a message may move from this state to `next`. Anything else is a bug and is rejected.
    public func canMove(to next: DeliveryState) -> Bool {
        switch (self, next) {
        case (.pending, .sending), (.pending, .failed):
            true
        case (.sending, .sent), (.sending, .failed), (.sending, .pending):
            // A send that lost its connection goes back to `.pending`, with the same id for the server to deduplicate.
            true
        case (.failed, .pending):
            // The user's Retry.
            true
        default:
            false
        }
    }

    /// True once the server has the message. Such a message is no longer shown as waiting.
    public var isSent: Bool {
        if case .sent = self { true } else { false }
    }

    /// The state name without its payload, as stored in the `state` column.
    var kind: String {
        switch self {
        case .pending: "pending"
        case .sending: "sending"
        case .sent: "sent"
        case .failed: "failed"
        }
    }
}

/// One outgoing message, kept until the server has it. It is the outbox row the app shows as "Waiting" or "Not sent".
public struct OutboundRecord: Sendable, Equatable, Identifiable, Codable {
    /// The client id. It doubles as the idempotency key the server sees, so a retried send is not delivered twice.
    public let id: UUID
    /// The chat the message belongs to.
    public let chatID: String
    /// The message text.
    public var text: String
    /// References to the message's attachments.
    public var attachmentRefs: [String]
    /// Where the message is in its delivery. Change it with ``move(to:)``.
    public private(set) var state: DeliveryState
    /// How many times a send was started.
    public private(set) var attempts: Int
    /// When the message was written.
    public let createdAt: Date

    /// Creates a pending message.
    public init(
        id: UUID = UUID(), chatID: String, text: String, attachmentRefs: [String] = [], createdAt: Date
    ) {
        self.id = id
        self.chatID = chatID
        self.text = text
        self.attachmentRefs = attachmentRefs
        self.state = .pending
        self.attempts = 0
        self.createdAt = createdAt
    }

    /// Moves the message to `next`. Throws ``OutboxError/illegalTransition(from:into:)`` when the move is not allowed.
    /// Each move into `.sending` counts one attempt.
    public mutating func move(to next: DeliveryState) throws {
        guard state.canMove(to: next) else {
            throw OutboxError.illegalTransition(from: state, into: next)
        }
        state = next
        if case .sending = next {
            attempts += 1
        }
    }
}
