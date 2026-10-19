extension TranscriptState {
    /// Applies one action. Pure: no I/O, no clock, no randomness.
    public mutating func apply(_ action: TranscriptAction) {
        switch action {
        case .event(let envelope, _):
            applyEvent(envelope)
        case .attached(let result):
            applyAttach(result)
        case .history(let messages):
            items = Self.items(from: messages)
            needsHistoryReload = false
            turn?.openSegmentID = nil
        case .userSubmitted(let localID, let text, let truncateBeforeRowID):
            if let rowID = truncateBeforeRowID { pendingTruncations[localID] = rowID }
            let entry = UserEntry(text: text, delivery: .sending)
            items.append(TranscriptItem(id: Self.localUserID(localID), content: .user(entry)))
        case .submitAcknowledged(let localID, let result):
            acknowledge(localID: localID, result: result)
        case .submitFailed(let localID, let message):
            pendingTruncations[localID] = nil
            updateUser(id: Self.localUserID(localID)) { $0.delivery = .failed(message) }
        case .notice(let localID, let text):
            items.append(TranscriptItem(id: "notice-\(localID)", content: .other(role: "system", text: text)))
        case .serverRequest(let request):
            addRequest(request, replayed: false)
        case .openRequestReplayed(let entry):
            let raw = RPCRequest(id: .string(entry.id), method: entry.method, params: entry.params as JSONValue?)
            guard let request = try? ServerRequest(request: raw) else { return }
            addRequest(request, replayed: true)
        case .requestAnswered(let id):
            openRequests.removeAll { $0.id == id }
        case .replayTruncated(let latestSeq):
            lastSeq = latestSeq
            needsHistoryReload = true
        }
    }

    /// Applies actions in order. Consecutive text deltas are merged first (see ``TranscriptCoalescer``).
    public mutating func apply(contentsOf actions: [TranscriptAction]) {
        for action in TranscriptCoalescer.coalesce(actions) {
            apply(action)
        }
    }

    // MARK: - Events

    private mutating func applyEvent(_ envelope: GatewayEventEnvelope) {
        if !envelope.sessionID.isEmpty, let live = liveSessionID, envelope.sessionID != live {
            if case .sessionReclaimed = envelope.event {} else { return }
        }
        if let seq = envelope.seq {
            if let last = lastSeq, seq <= last { return }
            lastSeq = seq
        }
        switch envelope.event {
        case .sessionInfo(let info):
            self.info = info
            if let title = info.title, !title.isEmpty { self.title = title }
            if let stored = info.storedSessionID { storedSessionID = stored }
            if let usage = info.usage { self.usage = usage }
        case .sessionTitle(let event):
            title = event.title
        case .messageStart:
            beginTurn()
        case .messageDelta(let delta):
            appendAssistantText(delta.text)
        case .messageInterim(let event):
            if !event.alreadyStreamed { appendInterim(event.text) }
        case .messageComplete(let event):
            completeTurn(event)
        case .reasoningAvailable(let delta):
            setReasoning { _ in delta.text }
        case .reasoningDelta(let delta):
            setReasoning { ($0 ?? "") + delta.text }
        case .thinkingDelta(let delta):
            withTurn { $0.spinnerText = delta.text.isEmpty ? nil : delta.text }
        case .statusUpdate(let event):
            withTurn { $0.statusLine = event.text }
        default:
            applyOtherEvent(envelope.event)
        }
    }

    private mutating func applyOtherEvent(_ event: GatewayEvent) {
        switch event {
        case .toolGenerating(let event):
            toolGenerating(event)
        case .toolStart(let event):
            toolStarted(event)
        case .toolComplete(let event):
            toolCompleted(event)
        case .toolOutputRisk(let event):
            updateTool(toolID: event.toolID) { $0.risk = event }
        case .requestCancel(let event):
            openRequests.removeAll { $0.id == event.id }
        case .approvalCancelled(let event):
            let ids = Set(event.requestIDs)
            openRequests.removeAll { $0.approvalRequestID.map(ids.contains) ?? false }
        case .sessionReclaimed(let event):
            if event.sessionID == liveSessionID {
                reclaimed = event
                turn = nil
                openRequests.removeAll()
            }
        case .sessionUsage(let event):
            usage = event.usage
        case .error(let event):
            lastError = event.message
            closeSegments()
            turn = nil
        case .subagentStart(let event), .subagentProgress(let event):
            updateSubagent(event) { _ in }
        case .subagentThinking(let event):
            updateSubagent(event) { $0.thinking = event.text ?? $0.thinking }
        case .subagentTool(let event):
            updateSubagent(event) { $0.currentTool = event.toolName ?? $0.currentTool }
        case .subagentComplete(let event):
            updateSubagent(event) {
                $0.status = event.status ?? .completed
                $0.summary = event.summary ?? event.text
                $0.currentTool = nil
            }
        case .todoUpdated(let event):
            if (todos?.revision ?? Int.min) <= event.revision { todos = event }
        default:
            break
        }
    }
}
