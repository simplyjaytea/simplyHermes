/// Everything the chat screen shows for one session, built only by ``TranscriptState/apply(_:)``.
///
/// The state is a value: the reducer never performs I/O, so the same actions always give the same state. The app
/// owns one per open session and feeds it gateway events, attach results and the user's own actions.
public struct TranscriptState: Sendable, Equatable {
    /// The live session id (8 hex). Events for other sessions are ignored once this is set.
    public var liveSessionID: String?
    /// The durable session id, which `session.resume` takes.
    public var storedSessionID: String?
    /// The session title.
    public var title: String?
    /// The last `session.info`.
    public var info: SessionInfo?
    /// Messages and tool calls, oldest first.
    public internal(set) var items: [TranscriptItem] = []
    /// The running turn, or nil when the session is idle.
    public internal(set) var turn: TurnActivity?
    /// Server requests waiting for the user (approvals, clarify, sudo, secret), oldest first.
    public internal(set) var openRequests: [PendingServerRequest] = []
    /// Delegated children, in the order they first appeared.
    public internal(set) var subagents: [SubagentState] = []
    /// The latest todo list, when the agent keeps one.
    public internal(set) var todos: TodoUpdatedEvent?
    /// The latest usage snapshot.
    public internal(set) var usage: Usage?
    /// Prompts queued behind a busy session.
    public internal(set) var queuedPrompts: [String] = []
    /// The highest event `seq` applied. Events at or below it are duplicates and are dropped.
    public internal(set) var lastSeq: Int?
    /// True when the replay ring overflowed: re-read the history and apply ``TranscriptAction/history(_:)``.
    public internal(set) var needsHistoryReload = false
    /// Set when another device took the session over or the server reaped it.
    public internal(set) var reclaimed: SessionReclaimedEvent?
    /// The last terminal `error` event text.
    public internal(set) var lastError: String?

    /// Counter for item ids that have no server id yet. Part of the state so ids stay deterministic.
    var nextLocalID = 0
    /// Edits waiting for `prompt.submit` to answer: local id to the row id the cut starts at. Rows are removed only
    /// when the server accepts the edit.
    var pendingTruncations: [String: Int] = [:]

    /// Creates an empty transcript, optionally bound to a live session.
    public init(liveSessionID: String? = nil, storedSessionID: String? = nil) {
        self.liveSessionID = liveSessionID
        self.storedSessionID = storedSessionID
    }
}

/// One row of the transcript. The id is stable for the life of the row, so views can animate it.
public struct TranscriptItem: Sendable, Equatable, Identifiable {
    /// Stable id, such as `row-157`, `user-local-3` or `tool-call_11438fb80bf2`.
    public var id: String
    /// What the row shows.
    public var content: Content

    /// The kinds of row.
    public enum Content: Sendable, Equatable {
        /// A user message, or a gateway-started prompt (cron, delegation) when `displayKind` is set.
        case user(UserEntry)
        /// Assistant text. A turn with tool calls has one segment before and after each call.
        case assistant(AssistantEntry)
        /// A tool call.
        case tool(ToolEntry)
        /// A stored message with a role the client does not render specially (for example `system`).
        case other(role: String, text: String)
    }

    /// The durable row id, when the server has one.
    public var rowID: Int? {
        switch content {
        case .user(let entry): entry.rowID
        case .assistant(let entry): entry.rowID
        case .tool(let entry): entry.rowID
        case .other: nil
        }
    }
}

/// A user message.
public struct UserEntry: Sendable, Equatable {
    /// The text.
    public var text: String
    /// Durable row id. Nil until `prompt.submit` answers, or forever for a queued prompt until history reloads.
    public var rowID: Int?
    /// Where the message is in delivery.
    public var delivery: Delivery
    /// Non-nil for turns the gateway started (cron, delegation). Render these as disclosures, not as the user.
    public var displayKind: String?
    /// Extra fields for ``displayKind``.
    public var displayMetadata: JSONValue?
    /// Unix seconds, when known.
    public var timestamp: Double?

    /// Delivery state of a user message.
    public enum Delivery: Sendable, Equatable {
        /// Sent, waiting for `prompt.submit` to answer.
        case sending
        /// The server stored it.
        case sent
        /// The session was busy; the server queued it.
        case queued
        /// `prompt.submit` failed with this message.
        case failed(String)
    }
}

/// One segment of assistant text.
public struct AssistantEntry: Sendable, Equatable {
    /// The text so far.
    public var text: String
    /// Model reasoning for this segment, when the model produced any.
    public var reasoning: String?
    /// True while deltas are still arriving.
    public var isStreaming: Bool
    /// Durable row id, when known.
    public var rowID: Int?
    /// Final status of the turn, set on the last segment by `message.complete`.
    public var status: TurnStatus?
    /// Error text of a failed turn.
    public var error: String?
    /// Warning text from `message.complete`.
    public var warning: String?
    /// Non-nil for gateway-started turns.
    public var displayKind: String?
    /// Extra fields for ``displayKind``.
    public var displayMetadata: JSONValue?
}

/// A tool call.
public struct ToolEntry: Sendable, Equatable {
    /// Where the call is.
    public enum Phase: Sendable, Equatable {
        /// The model is still writing the call (`tool.generating`); there is no tool id yet.
        case generating
        /// The call is running.
        case running
        /// The call finished.
        case completed
    }

    /// Tool call id from `tool.start`. Nil while generating.
    public var toolID: String?
    /// Tool name, such as `terminal`.
    public var name: String
    /// Where the call is.
    public var phase: Phase
    /// Short context line, such as the shell command.
    public var context: String?
    /// The call arguments.
    public var args: JSONValue?
    /// Preview line.
    public var preview: String?
    /// Surface labels.
    public var labels: [ToolLabel]?
    /// The result, as sent.
    public var result: JSONValue?
    /// The result as text, when sent (history rows carry only this).
    public var resultText: String?
    /// Summary line.
    public var summary: String?
    /// Inline diff for file edits.
    public var inlineDiff: String?
    /// Run time in seconds.
    public var durationSeconds: Double?
    /// Set when the output was flagged by `tool.output_risk`.
    public var risk: ToolOutputRiskEvent?
    /// Durable row id, when known.
    public var rowID: Int?
}

/// The running turn.
public struct TurnActivity: Sendable, Equatable {
    /// Cosmetic spinner text from `thinking.delta` ("formulating...", retry notices). Not model reasoning.
    public var spinnerText: String?
    /// The last `status.update` text, such as the provider retry notice.
    public var statusLine: String?
    /// Name of the tool running now, when any.
    public var activeTool: String?
    /// When the turn started (Unix seconds), when known.
    public var startedAt: Double?
    /// Id of the assistant segment receiving deltas. Nil between segments.
    var openSegmentID: String?
    /// Reasoning that arrived before any segment of the turn. Attached to the next segment.
    var pendingReasoning: String?
}

/// A server request waiting for the user.
public struct PendingServerRequest: Sendable, Equatable, Identifiable {
    /// The JSON-RPC id (`srq-...`). `request.cancel` names it.
    public var id: String
    /// The request, typed by method.
    public var request: ServerRequest
    /// True when it came from `open_requests` after a reconnect. Answer approvals with `approval.respond`.
    public var replayed: Bool

    /// The approval `request_id`, for approvals.
    public var approvalRequestID: String? {
        if case .approval(_, let approval) = request { return approval.requestID }
        return nil
    }
}

/// One delegated child agent.
public struct SubagentState: Sendable, Equatable, Identifiable {
    /// `subagent_id`, or `<delegation>#<index>` when the server sent none.
    public var id: String
    /// What the child was asked to do.
    public var goal: String
    /// Lifecycle status. Nil until the server names one.
    public var status: SubagentStatus?
    /// Latest status text (`subagent.thinking`).
    public var thinking: String?
    /// Tool in use now (`subagent.tool`).
    public var currentTool: String?
    /// Final summary.
    public var summary: String?
    /// The latest event, with every counter the server sent.
    public var latest: SubagentEvent
}

/// Inputs to ``TranscriptState/apply(_:)``.
public enum TranscriptAction: Sendable, Equatable {
    /// A gateway event. `replayed` is true when it came from `session.events.since`.
    case event(GatewayEventEnvelope, replayed: Bool)
    /// `session.create`, `session.resume` or `session.activate` answered. Rebuilds the state from the result.
    case attached(SessionAttachResult)
    /// The history was re-read (`session.history` or REST). Replaces the rows and clears
    /// ``TranscriptState/needsHistoryReload``.
    case history([TranscriptMessage])
    /// The user sent a prompt. With `truncateBeforeRowID` it is an edit: once the server accepts it, the rows from
    /// that user message up to the new prompt are removed.
    case userSubmitted(localID: String, text: String, truncateBeforeRowID: Int? = nil)
    /// `prompt.submit` answered for the prompt with `localID`.
    case submitAcknowledged(localID: String, PromptSubmitResult)
    /// `prompt.submit` failed for the prompt with `localID`.
    case submitFailed(localID: String, message: String)
    /// A line the app adds to the transcript itself, such as a slash command's output. It is not sent to the model.
    case notice(localID: String, text: String)
    /// A live server request arrived on this socket.
    case serverRequest(ServerRequest)
    /// `session.events.since` re-delivered an unanswered request.
    case openRequestReplayed(OpenRequestEntry)
    /// This client answered the request with this JSON-RPC id (or `approval.respond` succeeded for it).
    case requestAnswered(id: String)
    /// The replay ring overflowed; the watermark is now `latestSeq`.
    case replayTruncated(latestSeq: Int)
}
