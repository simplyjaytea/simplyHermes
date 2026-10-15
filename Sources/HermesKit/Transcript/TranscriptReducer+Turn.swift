// Turn, tool, request and attach steps of the transcript reducer.
extension TranscriptState {
    // MARK: - Turn

    mutating func beginTurn() {
        closeSegments()
        turn = TurnActivity(startedAt: info?.turnStartedAt)
        lastError = nil
    }

    /// Runs `body` on the running turn, starting one when events arrive without `message.start` (after a replay).
    mutating func withTurn(_ body: (inout TurnActivity) -> Void) {
        var current = turn ?? TurnActivity()
        body(&current)
        turn = current
    }

    mutating func appendAssistantText(_ text: String) {
        withTurn { _ in }
        if let id = turn?.openSegmentID, let index = items.firstIndex(where: { $0.id == id }) {
            updateAssistant(at: index) { $0.text += text }
            return
        }
        let id = nextID("assistant")
        let entry = AssistantEntry(text: text, reasoning: turn?.pendingReasoning, isStreaming: true)
        items.append(TranscriptItem(id: id, content: .assistant(entry)))
        turn?.pendingReasoning = nil
        turn?.openSegmentID = id
    }

    mutating func appendInterim(_ text: String) {
        closeSegments()
        let entry = AssistantEntry(text: text, reasoning: turn?.pendingReasoning, isStreaming: false)
        items.append(TranscriptItem(id: nextID("assistant"), content: .assistant(entry)))
        turn?.pendingReasoning = nil
    }

    /// Sets the reasoning of the segment it belongs to: the open segment, else the last segment of this turn.
    /// Reasoning that arrives before any segment waits for the next one.
    mutating func setReasoning(_ transform: (String?) -> String) {
        if let index = currentTurnAssistantIndex() {
            updateAssistant(at: index) { $0.reasoning = transform($0.reasoning) }
        } else {
            withTurn { $0.pendingReasoning = transform($0.pendingReasoning) }
        }
    }

    mutating func completeTurn(_ event: MessageCompleteEvent) {
        if let index = finalSegmentIndex(for: event) {
            updateAssistant(at: index) { entry in
                if let text = event.text, !text.isEmpty { entry.text = text }
                if entry.reasoning == nil { entry.reasoning = event.reasoning }
                entry.status = event.status
                entry.error = event.error
                entry.warning = event.warning
                entry.rowID = event.persistedTurn?.finalAssistantRowID ?? entry.rowID
            }
        } else if let error = event.error {
            lastError = error
        }
        if let userRowID = event.persistedTurn?.userRowID { markLastUserStored(rowID: userRowID) }
        if let usage = event.usage { self.usage = usage }
        closeSegments()
        turn = nil
    }

    /// The segment `message.complete` finishes: the open one, a new one for final text nobody streamed, or for a
    /// failed or interrupted turn the last one of the turn.
    private mutating func finalSegmentIndex(for event: MessageCompleteEvent) -> Int? {
        if let id = turn?.openSegmentID, let index = items.firstIndex(where: { $0.id == id }) { return index }
        if let text = event.text, !text.isEmpty, !lastTurnSegmentHasText(text) {
            let entry = AssistantEntry(text: text, reasoning: turn?.pendingReasoning, isStreaming: false)
            items.append(TranscriptItem(id: nextID("assistant"), content: .assistant(entry)))
            return items.count - 1
        }
        let failed = event.error != nil || event.status == .interrupted || event.status == .error
        return failed ? currentTurnAssistantIndex() : nil
    }

    private mutating func markLastUserStored(rowID: Int) {
        guard let index = items.lastIndex(where: { if case .user = $0.content { true } else { false } }) else {
            return
        }
        updateUser(at: index) { user in
            if user.rowID == nil { user.rowID = rowID }
            if user.delivery == .sending || user.delivery == .queued { user.delivery = .sent }
        }
    }

    /// Ends streaming on every segment and forgets the open one.
    mutating func closeSegments() {
        for index in items.indices {
            if case .assistant(var entry) = items[index].content, entry.isStreaming {
                entry.isStreaming = false
                items[index].content = .assistant(entry)
            }
        }
        turn?.openSegmentID = nil
    }

    /// The open segment, else the last assistant segment after the last user message.
    private func currentTurnAssistantIndex() -> Int? {
        if let id = turn?.openSegmentID, let index = items.firstIndex(where: { $0.id == id }) { return index }
        for index in items.indices.reversed() {
            switch items[index].content {
            case .assistant: return index
            case .user: return nil
            default: continue
            }
        }
        return nil
    }

    private func lastTurnSegmentHasText(_ text: String) -> Bool {
        guard let index = currentTurnAssistantIndex(), case .assistant(let entry) = items[index].content else {
            return false
        }
        return entry.text == text
    }

    // MARK: - Tools

    mutating func toolGenerating(_ event: ToolGeneratingEvent) {
        closeSegments()
        let entry = ToolEntry(name: event.name, phase: .generating)
        items.append(TranscriptItem(id: nextID("tool"), content: .tool(entry)))
        withTurn { $0.activeTool = event.name }
    }

    mutating func toolStarted(_ event: ToolStartEvent) {
        closeSegments()
        let placeholder = items.lastIndex { item in
            guard case .tool(let entry) = item.content else { return false }
            return entry.phase == .generating && entry.name == event.name
        }
        let index: Int
        if let placeholder {
            index = placeholder
        } else if let existing = toolIndex(event.toolID) {
            index = existing
        } else {
            let entry = ToolEntry(name: event.name, phase: .running)
            items.append(TranscriptItem(id: "tool-\(event.toolID)", content: .tool(entry)))
            index = items.count - 1
        }
        updateTool(at: index) { tool in
            tool.toolID = event.toolID
            tool.name = event.name
            tool.phase = .running
            tool.context = event.context
            tool.args = event.args
            tool.preview = event.preview
            tool.labels = event.labels
        }
        withTurn { $0.activeTool = event.name }
    }

    mutating func toolCompleted(_ event: ToolCompleteEvent) {
        if toolIndex(event.toolID) == nil {
            let entry = ToolEntry(toolID: event.toolID, name: event.name, phase: .running, args: event.args)
            items.append(TranscriptItem(id: "tool-\(event.toolID)", content: .tool(entry)))
        }
        updateTool(toolID: event.toolID) { tool in
            tool.phase = .completed
            tool.args = event.args ?? tool.args
            tool.result = event.result
            tool.resultText = event.resultText
            tool.summary = event.summary
            tool.inlineDiff = event.inlineDiff
            tool.durationSeconds = event.durationSeconds
            tool.labels = event.labels ?? tool.labels
        }
        if turn != nil { turn?.activeTool = nil }
    }

    mutating func updateTool(toolID: String, _ body: (inout ToolEntry) -> Void) {
        if let index = toolIndex(toolID) { updateTool(at: index, body) }
    }

    private func toolIndex(_ toolID: String) -> Int? {
        items.lastIndex { item in
            if case .tool(let entry) = item.content { return entry.toolID == toolID }
            return false
        }
    }

    // MARK: - Subagents and requests

    mutating func updateSubagent(_ event: SubagentEvent, _ body: (inout SubagentState) -> Void) {
        let id = event.subagentID ?? "\(event.delegationID ?? "")#\(event.taskIndex)"
        var state =
            subagents.first { $0.id == id }
            ?? SubagentState(id: id, goal: event.goal, status: nil, latest: event)
        state.goal = event.goal
        state.latest = event
        state.status = event.status ?? state.status ?? .running
        body(&state)
        if let index = subagents.firstIndex(where: { $0.id == id }) {
            subagents[index] = state
        } else {
            subagents.append(state)
        }
    }

    mutating func addRequest(_ request: ServerRequest, replayed: Bool) {
        if let live = liveSessionID, let session = request.sessionID, session != live { return }
        let pending = PendingServerRequest(id: request.id.description, request: request, replayed: replayed)
        let sameApproval = { (other: PendingServerRequest) in
            pending.approvalRequestID != nil && other.approvalRequestID == pending.approvalRequestID
        }
        if let index = openRequests.firstIndex(where: { $0.id == pending.id || sameApproval($0) }) {
            openRequests[index] = pending
        } else {
            openRequests.append(pending)
        }
    }

    // MARK: - Submit

    mutating func acknowledge(localID: String, result: PromptSubmitResult) {
        if let rowID = pendingTruncations.removeValue(forKey: localID) { cut(fromRowID: rowID, upTo: localID) }
        updateUser(id: Self.localUserID(localID)) { user in
            user.rowID = result.userRowID ?? user.rowID
            user.delivery = result.status == .queued ? .queued : .sent
        }
        guard let map = result.survivorRowIDMap else { return }
        for index in items.indices {
            guard let old = items[index].rowID, let mapped = map[String(old)], let new = mapped else { continue }
            setRowID(new, at: index)
        }
    }

    /// Removes the rows from the user message with `rowID` up to (not including) the prompt with `localID`.
    private mutating func cut(fromRowID rowID: Int, upTo localID: String) {
        guard let start = items.firstIndex(where: { $0.rowID == rowID }),
            let end = items.firstIndex(where: { $0.id == Self.localUserID(localID) }), start < end
        else { return }
        items.removeSubrange(start..<end)
    }

    mutating func updateUser(id: String, _ body: (inout UserEntry) -> Void) {
        if let index = items.firstIndex(where: { $0.id == id }) { updateUser(at: index, body) }
    }

    static func localUserID(_ localID: String) -> String { "user-\(localID)" }

    // MARK: - Attach

    mutating func applyAttach(_ result: SessionAttachResult) {
        if liveSessionID != result.sessionID { lastSeq = nil }
        liveSessionID = result.sessionID
        storedSessionID = result.storedSessionID ?? result.sessionKey ?? storedSessionID
        info = result.info
        if let title = result.info.title, !title.isEmpty { self.title = title }
        if let usage = result.info.usage { self.usage = usage }
        if result.messagesOmitted != true { items = Self.items(from: result.messages) }
        turn = nil
        openRequests = []
        reclaimed = nil
        needsHistoryReload = false
        queuedPrompts = result.queued.map { [$0.user] } ?? []
        if result.running == true || result.inflight?.streaming == true {
            turn = TurnActivity(startedAt: result.turnStartedAt)
        }
        if let inflight = result.inflight { applyInflight(inflight) }
        for entry in result.openRequests ?? [] { apply(.openRequestReplayed(entry)) }
        if let pending = result.pendingApproval, let request = pending.serverRequest(sessionID: result.sessionID) {
            addRequest(request, replayed: true)
        }
    }

    private mutating func applyInflight(_ inflight: InflightTurn) {
        let metadata = inflight.displayMetadata.map(JSONValue.object)
        if let user = inflight.user, !user.isEmpty, lastUserText() != user {
            let entry = UserEntry(
                text: user, delivery: .sent, displayKind: inflight.displayKind, displayMetadata: metadata)
            items.append(TranscriptItem(id: nextID("user"), content: .user(entry)))
        }
        let assistant = inflight.assistant ?? ""
        guard !assistant.isEmpty || inflight.streaming == true || inflight.error != nil else { return }
        let streaming = inflight.streaming == true && turn != nil
        let entry = AssistantEntry(
            text: assistant, isStreaming: streaming, error: inflight.error, displayKind: inflight.displayKind,
            displayMetadata: metadata)
        let id = nextID("assistant")
        items.append(TranscriptItem(id: id, content: .assistant(entry)))
        if streaming { turn?.openSegmentID = id }
    }

    private func lastUserText() -> String? {
        for item in items.reversed() {
            if case .user(let entry) = item.content { return entry.text }
        }
        return nil
    }

    /// Rows for stored messages. Ids come from row ids, or from the position when a row has none.
    static func items(from messages: [TranscriptMessage]) -> [TranscriptItem] {
        messages.enumerated().map { offset, message in
            let id = message.rowID.map { "row-\($0)" } ?? "history-\(offset)"
            return TranscriptItem(id: id, content: content(from: message))
        }
    }

    private static func content(from message: TranscriptMessage) -> TranscriptItem.Content {
        let text = message.text ?? message.content?.stringValue ?? ""
        switch message.role {
        case "user":
            return .user(
                UserEntry(
                    text: text, rowID: message.rowID, delivery: .sent, displayKind: message.displayKind,
                    displayMetadata: message.displayMetadata, timestamp: message.timestamp))
        case "assistant":
            return .assistant(
                AssistantEntry(
                    text: text, reasoning: message.reasoning, isStreaming: false, rowID: message.rowID,
                    displayKind: message.displayKind, displayMetadata: message.displayMetadata))
        case "tool":
            return .tool(
                ToolEntry(
                    toolID: message.toolCallID, name: message.name ?? "tool", phase: .completed,
                    context: message.context, args: message.args, labels: message.labels, resultText: text,
                    rowID: message.rowID))
        default:
            return .other(role: message.role, text: text)
        }
    }

    // MARK: - Item helpers

    mutating func nextID(_ prefix: String) -> String {
        nextLocalID += 1
        return "\(prefix)-local-\(nextLocalID)"
    }

    private mutating func updateAssistant(at index: Int, _ body: (inout AssistantEntry) -> Void) {
        guard case .assistant(var entry) = items[index].content else { return }
        body(&entry)
        items[index].content = .assistant(entry)
    }

    private mutating func updateUser(at index: Int, _ body: (inout UserEntry) -> Void) {
        guard case .user(var entry) = items[index].content else { return }
        body(&entry)
        items[index].content = .user(entry)
    }

    private mutating func updateTool(at index: Int, _ body: (inout ToolEntry) -> Void) {
        guard case .tool(var entry) = items[index].content else { return }
        body(&entry)
        items[index].content = .tool(entry)
    }

    private mutating func setRowID(_ rowID: Int, at index: Int) {
        switch items[index].content {
        case .user: updateUser(at: index) { $0.rowID = rowID }
        case .assistant: updateAssistant(at: index) { $0.rowID = rowID }
        case .tool: updateTool(at: index) { $0.rowID = rowID }
        case .other: break
        }
    }
}

extension ServerRequest {
    /// The live session the request belongs to, when it names one.
    var sessionID: String? {
        switch self {
        case .approval(_, let request): request.sessionID
        case .clarify(_, let request): request.sessionID
        case .sudo(_, let request): request.sessionID
        case .secret(_, let request): request.sessionID
        case .unknown(_, _, let params): params?["session_id"]?.stringValue
        }
    }
}

extension PendingApproval {
    /// The approval as a server request, so it shows as a card. Its id is `approval:<request_id>`; answer it with
    /// `approval.respond`.
    func serverRequest(sessionID: String) -> ServerRequest? {
        guard let requestID else { return nil }
        let approval = ApprovalRequest(
            sessionID: sessionID, requestID: requestID, command: command, description: description,
            patternKey: patternKey, patternKeys: patternKeys, allowPermanent: allowPermanent,
            allowSession: allowSession, smartDenied: smartDenied, choices: choices, toolName: toolName,
            gatewaySessionID: nil)
        return .approval(id: .string("approval:\(requestID)"), approval)
    }
}
