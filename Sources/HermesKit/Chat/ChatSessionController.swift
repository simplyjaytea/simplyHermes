import Foundation

/// What the controller needs from a gateway connection. ``GatewayClient`` conforms; tests use a fake.
public protocol ChatTransport: PromptSession {
    /// Calls `session.steer`: the text joins the next tool result without interrupting the turn.
    func steerSession(_ params: SessionSteerParams) async throws
    /// Calls `session.resume` and starts tracking the session so it survives a reconnect.
    func resumeSession(_ params: SessionResumeParams) async throws -> SessionAttachResult
    /// A new stream of client events.
    func clientEvents() async -> AsyncStream<GatewayClientEvent>
    /// Calls `image.attach_bytes`: queues an image for the next turn.
    func attachImage(_ params: ImageAttachBytesParams) async throws -> AttachedImageResult
    /// Calls `pdf.attach`: queues the pages of a PDF for the next turn.
    func attachPDF(_ params: PdfAttachParams) async throws -> PdfAttachResult
    /// Calls `file.attach`: stages a file in the session workspace.
    func attachFile(_ params: FileAttachParams) async throws -> FileAttachResult
    /// Calls `session.history`: the stored rows with their row ids.
    func sessionHistory(_ params: SessionHistoryParams) async throws -> SessionHistoryResult
    /// Calls `session.undo`: drops the last user turn and everything after it from an idle session.
    func undoSession(_ params: SessionUndoParams) async throws -> SessionUndoResult
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

    /// Calls `image.attach_bytes`.
    public func attachImage(_ params: ImageAttachBytesParams) async throws -> AttachedImageResult {
        try await call("image.attach_bytes", params: params)
    }

    /// Calls `pdf.attach`.
    public func attachPDF(_ params: PdfAttachParams) async throws -> PdfAttachResult {
        try await call("pdf.attach", params: params)
    }

    /// Calls `file.attach`.
    public func attachFile(_ params: FileAttachParams) async throws -> FileAttachResult {
        try await call("file.attach", params: params)
    }

    /// Calls `session.history`.
    public func sessionHistory(_ params: SessionHistoryParams) async throws -> SessionHistoryResult {
        try await call("session.history", params: params)
    }
}

/// The server refused an attachment, so the message was not sent.
public struct AttachmentRefused: Error, Equatable {
    /// Name of the refused file.
    public var name: String
    /// Reason the server gave, when it gave one.
    public var reason: String?

    /// Text for the failed message row.
    public var message: String {
        reason.map { "\(name): \($0)" } ?? "Hermes did not accept \(name)."
    }
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
    /// Events that came in while an edit waited for the server. Nil when no edit waits. They are applied after the cut.
    private var heldEvents: [GatewayClientEvent]?

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

    /// Sends a prompt with its files. While Hermes is busy the message waits in the queue and goes out when the turn
    /// ends, with its files.
    public func send(_ text: String, attachments: [ComposerAttachment] = []) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty, state.liveSessionID != nil else { return }
        if !isIdle || !queue.isEmpty {
            queue.enqueue(trimmed, attachments: attachments)
            publish()
            return
        }
        await submit(trimmed, attachments: attachments)
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

    /// Sends the last thing the user typed again, for Retry after a failed turn. Does nothing while a turn runs.
    public func retryLast() async {
        guard isIdle else { return }
        let last = state.items.reversed().compactMap { item -> String? in
            if case .user(let entry) = item.content, entry.displayKind == nil { return entry.text }
            return nil
        }.first
        guard let last else { return }
        await submit(last)
        await drainIfIdle()
    }

    /// Replaces the user turn at `rowID`, and every row after it, with `text` (edit and regenerate, WP-34). The old
    /// rows leave the transcript only when the server accepts the edit; until then nothing changes on screen. When the
    /// outcome asks a question, put it to the user and call again with ``TurnEditConfirmation/consent``. A stale row
    /// (`4018`) means this transcript is out of date, so the history is read again. Nil when no session is attached
    /// or another edit still waits for the server.
    public func edit(text: String, fromRowID rowID: Int, consent: TurnEditConsent = []) async -> TurnEditOutcome? {
        guard heldEvents == nil, let live = state.liveSessionID else { return nil }
        let editor = TurnEditor(session: transport, sessionID: live, profile: profile)
        let impact = RewindImpact.of(state, fromRowID: rowID)
        isSubmitting = true
        // The server can start the new turn before its answer reaches us. Holding the events back keeps the new reply
        // below the edited message, so the cut cannot take it away with the old rows.
        heldEvents = []
        let outcome = await editor.edit(text: text, fromRowID: rowID, impact: impact, consent: consent)
        switch outcome {
        case .done(let result):
            submitCount += 1
            let localID = "\(submitCount)"
            state.apply(.userSubmitted(localID: localID, text: text, truncateBeforeRowID: rowID))
            state.apply(.submitAcknowledged(localID: localID, result))
            awaitingTurn = result.status != .queued && state.turn == nil
            publish()
        case .stale:
            await reloadHistory()
        case .needsConfirmation, .busy, .failed:
            break
        }
        isSubmitting = false
        await releaseHeldEvents()
        await drainIfIdle()
        return outcome
    }

    /// Applies the events that were kept back while a cut waited for the server, in the order they came.
    private func releaseHeldEvents() async {
        let held = heldEvents ?? []
        heldEvents = nil
        for event in held { await handle(event) }
    }

    /// Reads the stored history again and shows it. Does nothing while a turn runs, since its text is not stored yet.
    private func reloadHistory() async {
        guard let live = state.liveSessionID, state.turn == nil else { return }
        let params = SessionHistoryParams(sessionID: live, profile: profile)
        guard let history = try? await transport.sessionHistory(params) else { return }
        show(history)
    }

    /// Shows the server's history as the transcript.
    private func show(_ history: SessionHistoryResult) {
        state.apply(.history(history.messages))
        publish()
    }

    /// Cuts the chat at the user turn `rowID` and everything after it, without sending anything (Rewind, WP-34).
    ///
    /// The server has no cut-only call. `session.undo` drops the last user turn and takes no row id, so a count made
    /// from the screen can remove turns nobody chose. This reads the history first and refuses when the user turns
    /// the server holds from `rowID` on are not the ones on screen. It then undoes one turn at a time and reads the
    /// history again after each call, so it stops as soon as `rowID` is gone and never reaches an older turn. The
    /// transcript ends as the server's history. A cut that erases the chat or drops several turns asks first: call
    /// again with ``TurnEditConfirmation/consent``. Nil when no session is attached or another cut still waits for
    /// the server.
    public func rewind(toRowID rowID: Int, consent: TurnEditConsent = []) async -> RewindOutcome? {
        guard heldEvents == nil, let live = state.liveSessionID else { return nil }
        guard isIdle else { return .busy }
        let impact = RewindImpact.of(state, fromRowID: rowID)
        if let question = TurnEditor.confirmation(for: impact, consent: consent) {
            return .needsConfirmation(question)
        }
        isSubmitting = true
        // Events wait, as in an edit, so none lands between the last undo and the history that replaces the rows.
        heldEvents = []
        let outcome = await undoTurns(from: rowID, live: live)
        isSubmitting = false
        await releaseHeldEvents()
        await drainIfIdle()
        return outcome
    }

    /// The work of ``rewind(toRowID:consent:)`` once nothing more needs asking.
    private func undoTurns(from rowID: Int, live: String) async -> RewindOutcome {
        let params = SessionHistoryParams(sessionID: live, profile: profile)
        var history: SessionHistoryResult
        do {
            history = try await transport.sessionHistory(params)
        } catch {
            return .failed(Self.rpcError(error))
        }
        let server = TranscriptState.items(from: history.messages)
        guard RewindImpact.agree(server, state.items, from: rowID),
            let text = Self.userText(in: server, rowID: rowID)
        else {
            show(history)
            return .changed
        }
        var remaining = Self.turnsLeft(in: history, from: rowID)
        do {
            while remaining > 0 {
                _ = try await transport.undoSession(SessionUndoParams(sessionID: live, profile: profile))
                history = try await transport.sessionHistory(params)
                let left = Self.turnsLeft(in: history, from: rowID)
                // Every call takes at least one of the turns we named. When it does not, stop asking.
                guard left < remaining else { break }
                remaining = left
            }
        } catch {
            // Turns dropped before the failure stay dropped, so show what the server has now.
            if let now = try? await transport.sessionHistory(params) { history = now }
            show(history)
            return .failed(Self.rpcError(error))
        }
        show(history)
        return remaining == 0 ? .done(text: text) : .changed
    }

    /// How many user turns from `rowID` on the history still holds. Zero once `rowID` is gone.
    private static func turnsLeft(in history: SessionHistoryResult, from rowID: Int) -> Int {
        RewindImpact.userRowIDs(in: TranscriptState.items(from: history.messages), from: rowID)?.count ?? 0
    }

    /// The text of the user row `rowID`.
    private static func userText(in items: [TranscriptItem], rowID: Int) -> String? {
        for item in items {
            if case .user(let entry) = item.content, entry.rowID == rowID { return entry.text }
        }
        return nil
    }

    private static func rpcError(_ error: any Error) -> RPCError {
        (error as? RPCError) ?? RPCError(code: HermesErrorCode.internalError, message: "\(error)")
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

    private func submit(_ text: String, attachments: [ComposerAttachment] = []) async {
        guard let live = state.liveSessionID else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        submitCount += 1
        let localID = "\(submitCount)"
        // Files go up first, so a refused file shows as a failed message and never reaches the prompt.
        let outgoing: String
        do {
            outgoing = try await upload(attachments, text: text, live: live)
        } catch {
            state.apply(.userSubmitted(localID: localID, text: Self.displayText(text, attachments)))
            state.apply(.submitFailed(localID: localID, message: Self.message(for: error)))
            publish()
            return
        }
        state.apply(.userSubmitted(localID: localID, text: outgoing))
        publish()
        do {
            let result = try await transport.submitPrompt(
                PromptSubmitParams(sessionID: live, text: outgoing, profile: profile))
            state.apply(.submitAcknowledged(localID: localID, result))
            awaitingTurn = result.status != .queued && state.turn == nil
        } catch {
            state.apply(.submitFailed(localID: localID, message: Self.message(for: error)))
        }
        publish()
    }

    /// Uploads the files in order. Returns the prompt text: the message, then the `@file:` references of the staged
    /// files. Without any text, it is the file names, so the message is never blank.
    private func upload(_ attachments: [ComposerAttachment], text: String, live: String) async throws -> String {
        var references: [String] = []
        for file in attachments {
            switch file.kind {
            case .image:
                let result = try await transport.attachImage(
                    ImageAttachBytesParams(
                        sessionID: live, profile: profile, contentBase64: file.data.base64EncodedString(),
                        filename: file.name))
                guard result.attached else { throw AttachmentRefused(name: file.name, reason: result.message) }
            case .pdf:
                let result = try await transport.attachPDF(
                    PdfAttachParams(
                        sessionID: live, profile: profile, contentBase64: file.data.base64EncodedString(),
                        filename: file.name))
                guard result.attached else { throw AttachmentRefused(name: file.name, reason: nil) }
            case .file:
                let result = try await transport.attachFile(
                    FileAttachParams(sessionID: live, profile: profile, dataURL: file.dataURL, name: file.name))
                guard result.attached else { throw AttachmentRefused(name: file.name, reason: nil) }
                references.append(result.refText)
            }
        }
        let parts = [text] + references
        let joined = parts.filter { !$0.isEmpty }.joined(separator: "\n")
        return joined.isEmpty ? Self.displayText("", attachments) : joined
    }

    /// The text of a message as the transcript shows it: the message, or the file names when there is no text.
    private static func displayText(_ text: String, _ attachments: [ComposerAttachment]) -> String {
        text.isEmpty ? attachments.map(\.name).joined(separator: ", ") : text
    }

    /// Sends the next waiting message when Hermes is free.
    private func drainIfIdle() async {
        // One message per idle moment: the next turn's events decide when the following one may go.
        guard isIdle, let next = queue.takeNext() else { return }
        publish()
        await submit(next.text, attachments: next.attachments)
    }

    /// Interrupts the running turn.
    public func stop() async {
        guard let live = state.liveSessionID else { return }
        try? await transport.interruptSession(SessionInterruptParams(sessionID: live, profile: profile))
    }

    /// Feeds one client event to the transcript. Public so tests and replays can drive it.
    public func handle(_ event: GatewayClientEvent) async {
        // An edit that waits for the server keeps the events back until its cut is in.
        if heldEvents != nil {
            heldEvents?.append(event)
            return
        }
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
        if let refused = error as? AttachmentRefused { return refused.message }
        return "\(error)"
    }
}
