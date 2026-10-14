/// Payload of `gateway.ready`, the first frame on every socket.
public struct GatewayReadyEvent: Sendable, Equatable, Codable {
    /// Colour tokens for the desktop UI. The client ignores them.
    public var skin: JSONValue?
    /// Whether the server sends change signal events (`sessions.changed`, `cron.changed`).
    public var changeEvents: Bool
    /// When true, send `gateway.ping` every 15 s. Any inbound frame counts as liveness.
    public var heartbeat: Bool?
    /// Server process id. A new value means the server restarted; old watermarks are invalid.
    public var replayEpoch: String

    enum CodingKeys: String, CodingKey {
        case skin
        case changeEvents = "change_events"
        case heartbeat
        case replayEpoch = "replay_epoch"
    }
}

/// Payload of `session.title`.
public struct SessionTitleEvent: Sendable, Equatable, Codable {
    /// The durable session id. The wire key is `session_id`, and it carries the stored id, not the live id.
    public var storedSessionID: String
    /// The new title.
    public var title: String

    enum CodingKeys: String, CodingKey {
        case storedSessionID = "session_id"
        case title
    }
}

/// Payload of the text-stream events: `message.delta`, `reasoning.delta`, `reasoning.available`, `thinking.delta`.
public struct StreamDelta: Sendable, Equatable, Codable {
    /// The text chunk.
    public var text: String
    /// Server-rendered form of the text, when provided.
    public var rendered: String?
    /// Whether the text is verbose output, when provided.
    public var verbose: Bool?
}

/// Payload of `message.interim`: text written before a tool call.
public struct MessageInterimEvent: Sendable, Equatable, Codable {
    /// The interim text.
    public var text: String
    /// True when the same text already streamed as `message.delta`.
    public var alreadyStreamed: Bool

    enum CodingKeys: String, CodingKey {
        case text
        case alreadyStreamed = "already_streamed"
    }
}

/// Payload of `message.complete`: the end of an assistant turn.
public struct MessageCompleteEvent: Sendable, Equatable, Codable {
    /// The final text. Partial when the turn was interrupted.
    public var text: String?
    /// Token and context usage for the turn.
    public var usage: Usage?
    /// Final status. `interrupted` for an interrupted turn.
    public var status: TurnStatus?
    /// Full reasoning text, when the model produced any.
    public var reasoning: String?
    /// A warning shown to the user, when set.
    public var warning: String?
    /// True when the response was previewed before sending.
    public var responsePreviewed: Bool?
    /// True when the response was reused from an earlier turn.
    public var responseReused: Bool?
    /// True when the response was transformed after generation.
    public var responseTransformed: Bool?
    /// Billing notice when the provider needs attention. Kept as raw JSON.
    public var billing: JSONValue?
    /// Short failure reason, when the turn failed.
    public var failureReason: String?
    /// Server-rendered final text, when provided.
    public var rendered: String?
    /// Error message, when the turn failed.
    public var error: String?
    /// Whether the failure can be retried.
    public var recoverable: Bool?
    /// Structured error detail (layer, code, retryable, provider, model). Kept as raw JSON.
    public var errorSurface: JSONValue?
    /// True when the turn ended early and the text is partial.
    public var partial: Bool?
    /// Durable row ids of the turn. Cache these for rewind.
    public var persistedTurn: PersistedTurn?

    enum CodingKeys: String, CodingKey {
        case text, usage, status, reasoning, warning, billing, rendered, error, recoverable, partial
        case responsePreviewed = "response_previewed"
        case responseReused = "response_reused"
        case responseTransformed = "response_transformed"
        case failureReason = "failure_reason"
        case errorSurface = "error_surface"
        case persistedTurn = "persisted_turn"
    }
}

/// Payload of `tool.generating`: the model started writing a tool call.
public struct ToolGeneratingEvent: Sendable, Equatable, Codable {
    /// The tool name.
    public var name: String
}

/// Payload of `tool.start`.
public struct ToolStartEvent: Sendable, Equatable, Codable {
    /// Id that links this event to `tool.complete`.
    public var toolID: String
    /// The tool name.
    public var name: String
    /// Short context line, such as the shell command.
    public var context: String?
    /// The call arguments. Kept as raw JSON.
    public var args: JSONValue?
    /// Arguments as text, when the server sends it.
    public var argsText: String?
    /// Preview line for the UI.
    public var preview: String?
    /// Labels that say which surface the call runs on.
    public var labels: [ToolLabel]?

    enum CodingKeys: String, CodingKey {
        case toolID = "tool_id"
        case name, context, args, preview, labels
        case argsText = "args_text"
    }
}

/// Payload of `tool.complete`.
public struct ToolCompleteEvent: Sendable, Equatable, Codable {
    /// Id that links this event to `tool.start`.
    public var toolID: String
    /// The tool name.
    public var name: String
    /// The call arguments. Kept as raw JSON.
    public var args: JSONValue?
    /// How long the call ran, in seconds.
    public var durationSeconds: Double?
    /// The tool result. Its shape depends on the tool, so it stays raw JSON.
    public var result: JSONValue?
    /// Short summary line, when provided.
    public var summary: String?
    /// The result as text, when provided.
    public var resultText: String?
    /// Inline diff text for file edits, when provided.
    public var inlineDiff: String?
    /// Todo items the tool produced, when any.
    public var todos: [JSONValue]?
    /// Revision of the todo list, when provided.
    public var revision: Int?
    /// Labels that say which surface the call ran on.
    public var labels: [ToolLabel]?

    enum CodingKeys: String, CodingKey {
        case args, summary, result, revision, labels, todos, name
        case toolID = "tool_id"
        case durationSeconds = "duration_s"
        case resultText = "result_text"
        case inlineDiff = "inline_diff"
    }
}

/// Payload of `tool.output_risk`: a tool output was flagged.
public struct ToolOutputRiskEvent: Sendable, Equatable, Codable {
    /// Id of the tool call.
    public var toolID: String
    /// The tool name.
    public var name: String
    /// Risk category, as the server names it.
    public var risk: String
    /// What was found.
    public var findings: [String]
    /// True when the output was redacted before display.
    public var redacted: Bool

    enum CodingKeys: String, CodingKey {
        case name, risk, findings, redacted
        case toolID = "tool_id"
    }
}

/// Payload of `status.update`, such as the provider retry notice.
public struct StatusUpdateEvent: Sendable, Equatable, Codable {
    /// Kind of status, for example `lifecycle`.
    public var kind: String
    /// Human-readable text. The error card reads this; there is no machine-readable retry field.
    public var text: String
}

/// Payload of `request.cancel`: a server request was answered or cancelled elsewhere.
public struct RequestCancelEvent: Sendable, Equatable, Codable {
    /// The JSON-RPC id of the cancelled server request.
    public var id: String
    /// The method of the cancelled request, such as `approval`.
    public var method: String
    /// Why it was cancelled, such as `resolved`.
    public var reason: String
}

/// Payload of `approval.cancelled`: pending approvals were cancelled on interrupt or reap.
public struct ApprovalCancelledEvent: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// The durable session id.
    public var storedSessionID: String
    /// Why the approvals were cancelled.
    public var reason: String
    /// How many approvals were cancelled.
    public var cancelledCount: Int
    /// The request ids that were cancelled.
    public var requestIDs: [String]

    enum CodingKeys: String, CodingKey {
        case reason
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
        case cancelledCount = "cancelled_count"
        case requestIDs = "request_ids"
    }
}

/// Payload of `session.reclaimed`: a detached session was reaped after its socket closed.
public struct SessionReclaimedEvent: Sendable, Equatable, Codable {
    /// The live session id that was reaped.
    public var sessionID: String
    /// The durable id, which `session.resume` takes to rebuild the session.
    public var storedSessionID: String
    /// Why it was reaped, for example `ws_orphan_reap`.
    public var reason: String

    enum CodingKeys: String, CodingKey {
        case reason
        case sessionID = "session_id"
        case storedSessionID = "stored_session_id"
    }
}

/// Payload of `session.usage`.
public struct SessionUsageEvent: Sendable, Equatable, Codable {
    /// The usage snapshot.
    public var usage: Usage
}

/// Payload of `error`: a terminal failure. Provider retries arrive as `status.update` instead.
public struct ErrorEvent: Sendable, Equatable, Codable {
    /// Error text.
    public var message: String
}

/// Payload of the `subagent.*` events. Only `goal`, `task_count` and `task_index` are always present.
public struct SubagentEvent: Sendable, Equatable, Codable {
    /// What the child was asked to do.
    public var goal: String
    /// How many tasks the delegation has.
    public var taskCount: Int
    /// Index of this task within the delegation.
    public var taskIndex: Int
    /// Id of the child agent.
    public var subagentID: String?
    /// Id of the parent agent, when any.
    public var parentID: String?
    /// Durable session id of the child.
    public var childSessionID: String?
    /// Id of the delegation this child belongs to.
    public var delegationID: String?
    /// Nesting depth, where 0 is a direct child.
    public var depth: Int?
    /// Model the child uses.
    public var model: String?
    /// How many tools the child has.
    public var toolCount: Int?
    /// Toolsets the child has.
    public var toolsets: [String]?
    /// Input tokens so far.
    public var inputTokens: Int?
    /// Output tokens so far.
    public var outputTokens: Int?
    /// Reasoning tokens so far.
    public var reasoningTokens: Int?
    /// Model calls so far.
    public var apiCalls: Int?
    /// Files the child read.
    public var filesRead: [String]?
    /// Files the child wrote.
    public var filesWritten: [String]?
    /// Recent tool calls, for the progress view. Kept as raw JSON.
    public var outputTail: [JSONValue]?
    /// Tool the child is using now (`subagent.tool`).
    public var toolName: String?
    /// Text the child produced (`subagent.thinking`, `subagent.start`).
    public var text: String?
    /// Lifecycle status.
    public var status: SubagentStatus?
    /// Final summary (`subagent.complete`).
    public var summary: String?
    /// How long the child ran, in seconds.
    public var durationSeconds: Double?
    /// Preview of the current tool call.
    public var toolPreview: String?

    enum CodingKeys: String, CodingKey {
        case goal, model, depth, toolsets, text, status, summary
        case taskCount = "task_count"
        case taskIndex = "task_index"
        case subagentID = "subagent_id"
        case parentID = "parent_id"
        case childSessionID = "child_session_id"
        case delegationID = "delegation_id"
        case toolCount = "tool_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case reasoningTokens = "reasoning_tokens"
        case apiCalls = "api_calls"
        case filesRead = "files_read"
        case filesWritten = "files_written"
        case outputTail = "output_tail"
        case toolName = "tool_name"
        case durationSeconds = "duration_seconds"
        case toolPreview = "tool_preview"
    }
}

/// Payload of `todo.updated`.
public struct TodoUpdatedEvent: Sendable, Equatable, Codable {
    /// The todo items. Kept as raw JSON; their shape is owned by the todo tool.
    public var todos: [JSONValue]
    /// Revision of the list.
    public var revision: Int
}

/// Empty payload for events that carry no fields (`message.start`, `sessions.changed`, `cron.changed`).
struct EmptyEventPayload: Sendable, Equatable, Codable {}
