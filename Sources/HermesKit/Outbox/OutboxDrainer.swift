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
    /// The server this chat lives on. Two servers can have a chat with the same id (the same Hermes saved under two
    /// addresses shares every id), and a message must only ever go to the server it was written for.
    private let connectionID: String
    private var submitter: any OutboxSubmitter
    private let clock: @Sendable () -> Date
    /// Who wants to hear when a state is written, by owner. A chat open in two windows has two owners, and both screens
    /// refresh; a closed model removes its own.
    private var observers: [UUID: @Sendable () async -> Void] = [:]
    private let pauses: OutboxPauses
    private var isDraining = false
    private var drainRequested = false

    /// Creates a drainer for one chat. Screens that want to hear about every state it writes, so they can show the
    /// change at once instead of after the whole pass, register with ``observe(owner:_:)``.
    public init(
        store: any OutboxStore, chatID: String, connectionID: String, submitter: any OutboxSubmitter,
        clock: @escaping @Sendable () -> Date = { Date() },
        pauses: OutboxPauses = .shared
    ) {
        self.pauses = pauses
        self.store = store
        self.chatID = chatID
        self.connectionID = connectionID
        self.submitter = submitter
        self.clock = clock
    }

    /// Points the drainer at a new submitter, when the chat reattaches on a new controller. A chat keeps one drainer
    /// for its life, so a pass that is still running finishes on the old submitter and the next one uses the new. A
    /// second drainer would not know about the message in flight and would send it again. Do not call
    /// ``recoverInterrupted()`` after this: it is for a relaunch, when nothing is in flight.
    public func use(_ submitter: any OutboxSubmitter) {
        self.submitter = submitter
    }

    /// Registers `onChange` for `owner` (a chat model). It runs after every state the drainer writes. Registering again
    /// under the same owner replaces that owner's callback and no other, so every open copy of a chat hears about changes
    /// and a model that reattaches does not hear twice.
    public func observe(owner: UUID, _ onChange: @escaping @Sendable () async -> Void) {
        observers[owner] = onChange
    }

    /// Removes `owner`'s callback. A chat model does this when it is retired. A model that is only detached (a closed
    /// tab, or Try again) keeps its callback, which refreshes its rows until it attaches again and registers under the
    /// same owner.
    public func stopObserving(owner: UUID) {
        observers[owner] = nil
    }

    private func notifyObservers() async {
        for onChange in Array(observers.values) { await onChange() }
    }

    /// Replaces `current` with `previous`, only if `current` is still the submitter: an attach that was abandoned after it
    /// swapped itself in puts back what it found. If another attach has swapped itself in since, that one stays.
    public func replace(_ current: any OutboxSubmitter, with previous: any OutboxSubmitter) {
        if (current as AnyObject) === (submitter as AnyObject) { submitter = previous }
    }

    /// The submitter now in use.
    public var currentSubmitter: any OutboxSubmitter { submitter }

    /// Puts messages that were being sent back to `pending`. Call it once, when the chat first attaches after a
    /// launch and before the first drain. Not on a later reattach: a message may be in flight then (see ``use(_:)``).
    public func recoverInterrupted() async throws {
        for record in try await ownRecords() where record.state.kind == .sending {
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
        var isFirstPass = true
        repeat {
            drainRequested = false
            if isFirstPass {
                try await sendPending()
            } else {
                // A later pass was asked for by another caller, such as a rebuilt chat model after this caller's
                // model detached and cancelled it. It must not inherit this caller's cancellation, or the next waiting
                // message would sit until some later trigger. An unstructured task doesn't (Dinesh's #133 review, M1).
                try await Task { try await self.sendPending() }.value
            }
            isFirstPass = false
        } while drainRequested
    }

    private func sendPending() async throws {
        for record in try await ownRecords() {
            // A cancelled drain sends nothing more. The message in flight, if any, is already recorded.
            if Task.isCancelled { return }
            // The chat is waiting out its Undo window after Delete: nothing more goes to it until Undo resumes it. The
            // check and the move to `sending` below are not one step, so a pause that lands in between lets this one
            // message go out. That is safe: it is sent, not lost (see OutboxPauses).
            if pauses.isPaused(chatID, connection: record.connectionID) { return }
            // A failed or stuck message holds back the ones written after it, so they keep the order the user wrote.
            if case .failed = record.state { return }
            if record.state.kind == .sending { return }
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
        await notifyObservers()
        try await drain()
    }

    /// This chat's messages on this drainer's server, oldest first. Another server's chat with the same id is not ours.
    private func ownRecords() async throws -> [OutboundRecord] {
        try await store.records(inChat: chatID).filter { $0.connectionID == connectionID }
    }

    private func move(_ id: UUID, to state: DeliveryState) async throws {
        // Written even when this drain was cancelled. A send the server accepted must not be left looking unsent, or
        // the next attach would send it again. An unstructured task does not inherit the cancellation.
        try await Task { try await store.updateState(state, forID: id) }.value
        await notifyObservers()
    }
}
