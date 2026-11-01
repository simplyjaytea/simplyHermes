import Foundation

/// What happened when a pending message was handed to the server.
public enum SubmitOutcome: Sendable, Equatable {
    /// The server accepted the prompt. The message is now `.sent`.
    case acknowledged
    /// The chat cannot take the message yet: Hermes is busy, or the session is not live. It stays pending.
    case deferred
    /// The server refused the prompt. The reason is for the user. The message stays pending for now.
    case failed(String)
}

/// Sends one persisted message to the server. A chat's controller is the implementation.
public protocol OutboxSubmitter: Sendable {
    /// Sends the message once. It must not queue the message: the outbox keeps it until the outcome is known.
    func deliver(_ record: OutboundRecord) async -> SubmitOutcome
}

/// Sends a chat's pending messages one at a time, oldest first, and records each outcome in the outbox.
///
/// A message goes out once per acknowledgement. The state moves `pending → sending → sent`, and a message that was
/// `sending` when the app was killed goes back to `pending` on the next attach (``recoverInterrupted()``). A message
/// is therefore delivered at least once, and exactly once except when the app dies between sending and the ack.
public actor OutboxDrainer {
    private let store: any OutboxStore
    private let chatID: String
    private let submitter: any OutboxSubmitter
    private let clock: @Sendable () -> Date
    private var isDraining = false
    private var drainRequested = false

    /// Creates a drainer for one chat.
    public init(
        store: any OutboxStore, chatID: String, submitter: any OutboxSubmitter,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.chatID = chatID
        self.submitter = submitter
        self.clock = clock
    }

    /// Puts messages that were being sent back to `pending`. Call it once per attach, before the first drain.
    public func recoverInterrupted() async throws {
        for record in try await store.records(inChat: chatID) where record.state.kind == "sending" {
            try await store.updateState(.pending, forID: record.id)
        }
    }

    /// Sends the pending messages in order. It stops at the first message that is deferred or fails, and the next
    /// drain picks that message up. A drain requested while one is running is folded into it, so no message is sent
    /// twice at once.
    public func drain() async throws {
        if isDraining {
            drainRequested = true
            return
        }
        isDraining = true
        defer { isDraining = false }
        repeat {
            drainRequested = false
            try await sendPending()
        } while drainRequested
    }

    private func sendPending() async throws {
        for record in try await store.records(inChat: chatID) where record.state == .pending {
            try await store.updateState(.sending, forID: record.id)
            switch await submitter.deliver(record) {
            case .acknowledged:
                try await store.updateState(.sent(acknowledgedAt: clock()), forID: record.id)
            case .deferred, .failed:
                try await store.updateState(.pending, forID: record.id)
                return
            }
        }
    }
}
