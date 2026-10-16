import Foundation

/// What the controller needs from a gateway connection. ``GatewayClient`` conforms; tests use a fake.
public protocol ChatTransport: PromptSession {
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
    private var submitCount = 0
    private var eventTask: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<TranscriptState>.Continuation] = [:]

    /// Creates a controller for the stored session `storedSessionID`. Nothing happens until ``attach()``.
    public init(transport: any ChatTransport, storedSessionID: String, profile: String? = nil) {
        self.transport = transport
        self.storedSessionID = storedSessionID
        self.profile = profile
        self.state = TranscriptState(storedSessionID: storedSessionID)
    }

    /// The current transcript.
    public var current: TranscriptState { state }

    /// A stream of the transcript, starting with the current value and yielding after every change.
    public func states() -> AsyncStream<TranscriptState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<TranscriptState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        subscribers[id] = continuation
        continuation.yield(state)
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

    /// Sends a prompt. The row shows at once as sending, then as sent, queued or failed.
    public func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let live = state.liveSessionID else { return }
        submitCount += 1
        let localID = "\(submitCount)"
        state.apply(.userSubmitted(localID: localID, text: trimmed))
        publish()
        let busy = state.turn != nil
        do {
            let params = PromptSubmitParams(sessionID: live, text: trimmed, profile: profile, queued: busy ? true : nil)
            let result = try await transport.submitPrompt(params)
            state.apply(.submitAcknowledged(localID: localID, result))
        } catch {
            state.apply(.submitFailed(localID: localID, message: Self.message(for: error)))
        }
        publish()
    }

    /// Interrupts the running turn.
    public func stop() async {
        guard let live = state.liveSessionID else { return }
        try? await transport.interruptSession(SessionInterruptParams(sessionID: live, profile: profile))
    }

    /// Feeds one client event to the transcript. Public so tests and replays can drive it.
    public func handle(_ event: GatewayClientEvent) {
        guard let action = TranscriptAction(event) else { return }
        state.apply(action)
        publish()
    }

    private func publish() {
        for continuation in subscribers.values { continuation.yield(state) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private static func message(for error: any Error) -> String {
        if let rpc = error as? RPCError { return rpc.message }
        return "\(error)"
    }
}
