import Foundation

/// What the controller needs from a gateway connection. ``GatewayClient`` conforms; tests use a fake.
public protocol ChatTransport: PromptSession {
    /// Calls `session.steer`: the text joins the next tool result without interrupting the turn.
    func steerSession(_ params: SessionSteerParams) async throws
    /// Calls `session.resume` and starts tracking the session so it survives a reconnect.
    func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult
    /// A new stream of client events.
    func clientEvents() async -> AsyncStream<GatewayClientEvent>
}

extension GatewayClient: ChatTransport {
    /// Calls `session.resume` and tracks the live session.
    public func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult {
        let result: SessionAttachResult = try await call("session.resume", params: params)
        track(liveID: result.sessionID, storedID: result.storedSessionID ?? params.sessionID)
        return result
    }

    /// Calls `session.steer`.
    public func steerSession(_ params: SessionSteerParams) async throws {
        let _: JSONValue = try await call("session.steer", params: params)
    }

    /// The client's event stream.
    public func clientEvents() async -> AsyncStream<GatewayClientEvent> { events() }
}

/// Owns the ``TranscriptState`` of one open chat: resumes the session, feeds gateway events to the reducer,
/// sends prompts and stops the running turn. It performs the I/O the reducer leaves out.
public actor ChatSessionController {
    private let transport: any ChatTransport
    private let storedSessionID: String
    private let profile: String?
    private var state: TranscriptState
    private var queue = MessageQueue()
    private var submitCount = 0
    private var isSubmitting = false
    /// True from an accepted prompt until its turn shows up in the events, so a queued message cannot overtake it.
    private var awaitingTurn = false

    private var isIdle: Bool { state.turn == nil && !isSubmitting && !awaitingTurn }
    private var eventTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<ChatSnapshot>.Continuation] = [:]

    /// Creates a controller for the stored session `storedSessionID`. Nothing happens until ``attach()``.
    public init(transport: any ChatTransport, storedSessionID: String, profile: String? = nil) {
        self.transport = transport
        self.storedSessionID = storedSessionID
        self.profile = profile
        self.state = TranscriptState(storedSessionID: storedSessionID)
    }

    /// The current transcript.
    public var current: TranscriptState { state }

    /// The messages waiting for Hermes to be free.
    public var pendingMessages: MessageQueue { queue }

    /// A stream of the transcript, starting with the current value and yielding after every change.
    public func states() -> AsyncStream<ChatSnapshot> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<ChatSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(ChatSnapshot(transcript: state, queue: queue))
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        return stream
    }

    /// Subscribes to events, then resumes the session and shows its history.
    public func attach() async throws {
        guard eventTask == nil else { return }
        let events = await transport.clientEvents()
        eventTask = Task { [weak self] in
            for await event in events {
                await self?.handle(event)
            }
        }
        let result = try await transport.resumeSession(
            SessionResumeParams(sessionID: storedSessionID, profile: profile))
        state.apply(.attached(result))
        publish()
    }

    /// Stops listening. The transcript stays readable.
    public func detach() {
        eventTask?.cancel()
        eventTask = nil
    }

    /// Sends a prompt. While Hermes is busy the message waits in the queue and goes out when the turn ends.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.liveSessionID != nil else { return }
        if !isIdle || !queue.isEmpty {
            queue.enqueue(trimmed)
            publish()
            return
        }
        await submit(trimmed)
        await drainIfIdle()
    }

    /// Injects text into the running turn (`session.steer`) without interrupting it. Returns false when nothing
    /// is running or the server refused.
    @discardableResult
    public func steer(_ text: String) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, state.turn != nil, let live = state.liveSessionID else { return false }
        do {
            try await transport.steerSession(SessionSteerParams(sessionID: live, text: trimmed, profile: profile))
            return true
        } catch {
            return false
        }
    }

    /// Changes the text of a waiting message. Blank text removes it.
    public func editQueued(_ id: Int, to text: String) {
        queue.edit(id, to: text)
        publish()
    }

    /// Removes a waiting message.
    public func removeQueued(_ id: Int) {
        queue.remove(id)
        publish()
    }

    /// Moves a waiting message to a new position.
    public func moveQueued(_ id: Int, to position: Int) {
        queue.move(id, to: position)
        publish()
    }

    /// Holds or releases the queue. Releasing sends the next message at once when Hermes is free.
    public func setQueuePaused(_ paused: Bool) async {
        queue.isPaused = paused
        publish()
        if !paused { await drainIfIdle() }
    }

    private func submit(_ text: String) async {
        guard let live = state.liveSessionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        submitCount += 1
        let localID = "\(submitCount)"
        state.apply(.userSubmitted(localID: localID, text: text))
        publish()
        do {
            let result = try await transport.submitPrompt(
                PromptSubmitParams(sessionID: live, text: text, profile: profile))
            state.apply(.submitAcknowledged(localID: localID, result))
            awaitingTurn = result.status != .queued && state.turn == nil
        } catch {
            state.apply(.submitFailed(localID: localID, message: Self.message(for: error)))
        }
        publish()
    }

    /// Sends the next waiting message when Hermes is free.
    private func drainIfIdle() async {
        // One message per idle moment: the next turn's events decide when the following one may go.
        guard isIdle, let next = queue.takeNext() else { return }
        publish()
        await submit(next.text)
    }

    /// Interrupts the running turn.
    public func stop() async {
        guard let live = state.liveSessionID else { return }
        try? await transport.interruptSession(SessionInterruptParams(sessionID: live, profile: profile))
    }

    /// Feeds one client event to the transcript. Public so tests and replays can drive it.
    public func handle(_ event: GatewayClientEvent) async {
        guard let action = TranscriptAction(event) else { return }
        state.apply(action)
        if state.turn != nil { awaitingTurn = false }
        if case .event(let envelope, _) = action {
            switch envelope.event {
            case .messageComplete, .error: awaitingTurn = false
            default: break
            }
        }
        publish()
        await drainIfIdle()
    }

    private func publish() {
        for continuation in subscribers.values { continuation.yield(ChatSnapshot(transcript: state, queue: queue)) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private static func message(for error: any Error) -> String {
        if let rpc = error as? RPCError { return rpc.message }
        return "\(error)"
    }
}
