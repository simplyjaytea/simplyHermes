import Foundation

/// What happened when a pending message was handed to the server.
public enum SubmitOutcome: Sendable, Equatable {
    /// The server accepted the prompt. The message is now `.sent`.
    case acknowledged
    /// The chat cannot take the message yet: Hermes is busy, or the session is not live. It stays pending.
    case deferred
    /// The server refused the prompt. The reason is for the user. The message is kept as failed, until the user retries
    /// it or deletes it.
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
    private let onChange: @Sendable () async -> Void
    private var isDraining = false
    private var drainRequested = false

    /// Creates a drainer for one chat. `onChange` runs after every state the drainer writes, so the screen can show
    /// the change at once instead of after the whole pass.
    public init(
        store: any OutboxStore, chatID: String, submitter: any OutboxSubmitter,
        clock: @escaping @Sendable () -> Date = { Date() },
        onChange: @escaping @Sendable () async -> Void = {}
    ) {
        self.store = store
        self.chatID = chatID
        self.submitter = submitter
        self.clock = clock
        self.onChange = onChange
    }

    /// Puts messages that were being sent back to `pending`. Call it once per attach, before the first drain.
    public func recoverInterrupted() async throws {
        for record in try await store.records(inChat: chatID) where record.state.kind == .sending {
            try await move(record.id, to: .pending)
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
        for record in try await store.records(inChat: chatID) {
            // A failed message holds back the ones written after it, so they keep the order the user wrote them in.
            if case .failed = record.state { return }
            guard record.state == .pending else { continue }
            try await move(record.id, to: .sending)
            switch await submitter.deliver(record) {
            case .acknowledged:
                try await move(record.id, to: .sent(acknowledgedAt: clock()))
            case .deferred:
                try await move(record.id, to: .pending)
                return
            case .failed(let reason):
                // The user decides what happens next (Retry, Edit or Delete). Later messages wait behind it.
                try await move(record.id, to: .failed(reason: reason))
                return
            }
        }
    }

    /// Retries a failed message, then sends the waiting messages. Only a failed message can be retried: a retry that
    /// races a send in flight throws and changes nothing, so the message cannot go out twice.
    public func retry(_ id: UUID) async throws {
        try await store.updateState(.pending, forID: id, ifCurrently: .failed)
        await onChange()
        try await drain()
    }

    private func move(_ id: UUID, to state: DeliveryState) async throws {
        try await store.updateState(state, forID: id)
        await onChange()
    }
}
