/// Token and context usage. Returned by `session.usage`, and inside `message.complete` and `session.info`.
public struct Usage: Sendable, Equatable, Codable {
    /// Model the usage is for.
    public var model: String
    /// Input tokens.
    public var input: Int
    /// Output tokens.
    public var output: Int
    /// Reasoning tokens.
    public var reasoning: Int
    /// Prompt tokens.
    public var prompt: Int
    /// Completion tokens.
    public var completion: Int
    /// Total tokens.
    public var total: Int
    /// Model calls made.
    public var calls: Int
    /// Context compressions so far.
    public var compressions: Int?
    /// Tokens in the context now.
    public var contextUsed: Int?
    /// Size of the context window.
    public var contextMax: Int?
    /// Context use as a percentage of the window.
    public var contextPercent: Double?
    /// Where the context figure came from, for example `provider_usage`.
    public var contextSource: String?
    /// True when the context figure is an estimate.
    public var contextEstimated: Bool?
    /// Cache hit rate as a percentage.
    public var cacheHitPct: Double?
    /// Tokens read from the cache.
    public var cacheRead: Int?
    /// Tokens written to the cache.
    public var cacheWrite: Int?
    /// Average model latency, in seconds.
    public var avgLatencySeconds: Double?
    /// Average tokens per second.
    public var avgTokensPerSecond: Double?
    /// Subagents running now.
    public var activeSubagents: Int?
    /// Developer credits spent, in millionths.
    public var devCreditsSpentMicros: Int?
    /// Cost in US dollars, when known.
    public var costUSD: Double?
    /// Status of the cost figure.
    public var costStatus: String?
    /// Human-readable credit lines.
    public var creditsLines: [String]?

    enum CodingKeys: String, CodingKey {
        case model, input, output, reasoning, prompt, completion, total, calls, compressions
        case contextUsed = "context_used"
        case contextMax = "context_max"
        case contextPercent = "context_percent"
        case contextSource = "context_source"
        case contextEstimated = "context_estimated"
        case cacheHitPct = "cache_hit_pct"
        case cacheRead = "cache_read"
        case cacheWrite = "cache_write"
        case avgLatencySeconds = "avg_latency_s"
        case avgTokensPerSecond = "avg_tps"
        case activeSubagents = "active_subagents"
        case devCreditsSpentMicros = "dev_credits_spent_micros"
        case costUSD = "cost_usd"
        case costStatus = "cost_status"
        case creditsLines = "credits_lines"
    }
}

/// Durable row ids of a finished turn, from `message.complete`. Cache them for rewind.
public struct PersistedTurn: Sendable, Equatable, Codable {
    /// Row ids written for the turn.
    public var rowIDs: [Int]
    /// True when every row of the turn was written.
    public var complete: Bool
    /// Row id of the user message.
    public var userRowID: Int?
    /// Row id of the final assistant message.
    public var finalAssistantRowID: Int?

    enum CodingKeys: String, CodingKey {
        case complete
        case rowIDs = "row_ids"
        case userRowID = "user_row_id"
        case finalAssistantRowID = "final_assistant_row_id"
    }
}

/// Label that says which surface a tool call runs on. Every field is optional.
public struct ToolLabel: Sendable, Equatable, Codable {
    /// Surface kind.
    public var kind: ToolLabelKind?
    /// App name, for connector calls.
    public var app: String?
    /// Action name.
    public var action: String?
    /// Emoji for the UI.
    public var emoji: String?
    /// Display text.
    public var text: String?
    /// Tool or server name.
    public var name: String?
    /// Preview line.
    public var preview: String?
}

/// The project a session belongs to.
public struct ProjectRef: Sendable, Equatable, Codable {
    /// Project id.
    public var id: String
    /// Project slug.
    public var slug: String
    /// Project name.
    public var name: String
    /// Main path of the project, when set.
    public var primaryPath: String?

    enum CodingKeys: String, CodingKey {
        case id, slug, name
        case primaryPath = "primary_path"
    }
}

/// Status of one MCP server attached to a session.
public struct McpServerStatus: Sendable, Equatable, Codable {
    /// Server name.
    public var name: String?
    /// Status text.
    public var status: String?
    /// Number of tools the server exposes.
    public var toolCount: Int?
    /// Error text, when the server failed.
    public var error: String?

    enum CodingKeys: String, CodingKey {
        case name, status, error
        case toolCount = "tool_count"
    }
}

/// Live session state, from `session.info` and from the `info` of create, resume and activate results.
///
/// Every field is optional: the server sends a subset in some results. Unknown keys are ignored.
public struct SessionInfo: Sendable, Equatable, Codable {
    /// Model name.
    public var model: String?
    /// Provider name.
    public var provider: String?
    /// Reasoning effort setting.
    public var reasoningEffort: String?
    /// Reasoning effort as sent on the wire.
    public var reasoningEffortWire: String?
    /// Service tier.
    public var serviceTier: String?
    /// Whether fast mode is on.
    public var fast: Bool?
    /// Whether approvals are skipped (yolo mode).
    public var yolo: Bool?
    /// Approval mode, for example `smart`.
    public var approvalMode: String?
    /// Tools by toolset name.
    public var tools: [String: [String]]?
    /// Skills by category.
    public var skills: [String: [String]]?
    /// Working directory on the server.
    public var cwd: String?
    /// Git branch of the working directory.
    public var branch: String?
    /// Project the session belongs to.
    public var project: ProjectRef?
    /// Terminal backend, for example `local`.
    public var terminalBackend: String?
    /// Personality setting.
    public var personality: String?
    /// True while a turn runs.
    public var running: Bool?
    /// When the running turn started (Unix seconds).
    public var turnStartedAt: Double?
    /// Session title.
    public var title: String?
    /// Durable session id.
    public var storedSessionID: String?
    /// Protocol number of the server. An integer in practice (`8`). Kept raw because the contract allows a string.
    public var desktopContract: JSONValue?
    /// Server version. `"unknown"` on git builds.
    public var version: String?
    /// Server release date, for example `2026.9.24`.
    public var releaseDate: String?
    /// Update notice, when the server is behind. Kept raw.
    public var updateBehind: JSONValue?
    /// Command that updates the server.
    public var updateCommand: String?
    /// Usage so far.
    public var usage: Usage?
    /// Profile the session runs under.
    public var profileName: String?
    /// MCP servers attached to the session.
    public var mcpServers: [McpServerStatus]?
    /// System prompt. Long; only present when the server sends it.
    public var systemPrompt: String?
    /// Credential warning text, when a credential is missing.
    public var credentialWarning: String?
    /// True when the session is created lazily.
    public var lazy: Bool?

    enum CodingKeys: String, CodingKey {
        case model, provider, fast, yolo, tools, skills, cwd, branch, project, personality, running, title, version
        case usage, lazy
        case reasoningEffort = "reasoning_effort"
        case reasoningEffortWire = "reasoning_effort_wire"
        case serviceTier = "service_tier"
        case approvalMode = "approval_mode"
        case terminalBackend = "terminal_backend"
        case turnStartedAt = "turn_started_at"
        case storedSessionID = "stored_session_id"
        case desktopContract = "desktop_contract"
        case releaseDate = "release_date"
        case updateBehind = "update_behind"
        case updateCommand = "update_command"
        case profileName = "profile_name"
        case mcpServers = "mcp_servers"
        case systemPrompt = "system_prompt"
        case credentialWarning = "credential_warning"
    }
}

/// One message of a transcript. `row_id` is the durable id, used to rewind.
public struct TranscriptMessage: Sendable, Equatable, Codable {
    /// `user`, `assistant`, `tool` or `system`.
    public var role: String
    /// Plain text of the message.
    public var text: String?
    /// Structured content. Kept raw.
    public var content: JSONValue?
    /// Id of the tool call this message answers.
    public var toolCallID: String?
    /// When the message was written (Unix seconds).
    public var timestamp: Double?
    /// Durable row id.
    public var rowID: Int?
    /// How the UI should display the message.
    public var displayKind: String?
    /// Metadata for the display kind. Kept raw.
    public var displayMetadata: JSONValue?
    /// Tool name, for tool messages.
    public var name: String?
    /// Tool context line.
    public var context: String?
    /// Tool arguments. Kept raw.
    public var args: JSONValue?
    /// Surface labels for tool messages.
    public var labels: [ToolLabel]?
    /// Reasoning text, when stored.
    public var reasoning: String?

    enum CodingKeys: String, CodingKey {
        case role, text, content, timestamp, name, context, args, labels, reasoning
        case toolCallID = "tool_call_id"
        case rowID = "row_id"
        case displayKind = "display_kind"
        case displayMetadata = "display_metadata"
    }
}

/// The turn that was running when a socket attached to a live session.
public struct InflightTurn: Sendable, Equatable, Codable {
    /// Assistant text streamed so far.
    public var assistant: String?
    /// True while the text is still streaming.
    public var streaming: Bool?
    /// The user prompt of the turn.
    public var user: String?
    /// How the UI should display the turn.
    public var displayKind: String?
    /// Display metadata. Kept as a map of raw values.
    public var displayMetadata: [String: JSONValue]?
    /// Corrections the user sent while the turn ran.
    public var corrections: [String]?
    /// Character offsets of the corrections.
    public var correctionOffsets: [Int]?
    /// Error text, when the turn failed.
    public var error: String?
    /// Status text.
    public var status: String?
    /// Whether the failure can be retried.
    public var recoverable: Bool?
    /// Structured error detail. Kept raw.
    public var errorSurface: JSONValue?

    enum CodingKeys: String, CodingKey {
        case assistant, streaming, user, corrections, error, status, recoverable
        case displayKind = "display_kind"
        case displayMetadata = "display_metadata"
        case correctionOffsets = "correction_offsets"
        case errorSurface = "error_surface"
    }
}

/// A prompt waiting behind a busy session. Surfaced in `session.resume`.
public struct QueuedPrompt: Sendable, Equatable, Codable {
    /// The queued user text.
    public var user: String
}

/// An approval the server is waiting on, as shown in `session.resume` and `session.activate`.
public struct PendingApproval: Sendable, Equatable, Codable {
    /// Id of the approval request.
    public var requestID: String?
    /// The command awaiting approval.
    public var command: String?
    /// Why the command needs approval.
    public var description: String?
    /// Pattern that matched the command.
    public var patternKey: String?
    /// Patterns that matched the command.
    public var patternKeys: [String]?
    /// Whether "always" is offered.
    public var allowPermanent: Bool?
    /// Whether "session" is offered.
    public var allowSession: Bool?
    /// Whether the command was denied by smart approval.
    public var smartDenied: Bool?
    /// Choices offered.
    public var choices: [ApprovalChoice]?
    /// Tool that asked for approval.
    public var toolName: String?

    enum CodingKeys: String, CodingKey {
        case command, description, choices
        case requestID = "request_id"
        case patternKey = "pattern_key"
        case patternKeys = "pattern_keys"
        case allowPermanent = "allow_permanent"
        case allowSession = "allow_session"
        case smartDenied = "smart_denied"
        case toolName = "tool_name"
    }
}

/// A server request that is still unanswered. Re-delivered on reconnect; treat it as live but replayed.
public struct OpenRequestEntry: Sendable, Equatable, Codable {
    /// JSON-RPC id of the request.
    public var id: String
    /// Method, such as `approval` or `clarify`.
    public var method: String
    /// The request params, exactly as sent.
    public var params: JSONValue
}

/// A message to seed a new session with (`session.create`).
public struct SeedMessage: Sendable, Equatable, Codable {
    /// `user` or `assistant`.
    public var role: String
    /// Message content.
    public var content: String?
    /// Message text, when sent instead of content.
    public var text: String?
    /// How the UI should display the message.
    public var displayKind: String?

    /// Creates a seed message.
    public init(role: String, content: String? = nil, text: String? = nil, displayKind: String? = nil) {
        self.role = role
        self.content = content
        self.text = text
        self.displayKind = displayKind
    }

    enum CodingKeys: String, CodingKey {
        case role, content, text
        case displayKind = "display_kind"
    }
}

/// Result of `session.usage`: the usage snapshot.
public typealias SessionUsageResult = Usage

/// Result of `session.create`, `session.resume` and `session.activate`. They share one shape.
///
/// `session.resume` takes the stored id and `session.activate` takes the live id. Give each its own id, not this one.
public struct SessionAttachResult: Sendable, Equatable, Codable {
    /// The live session id. Use it in events and most params.
    public var sessionID: String
    /// Number of messages in the transcript.
    public var messageCount: Int
    /// The transcript.
    public var messages: [TranscriptMessage]
    /// Live session state.
    public var info: SessionInfo
    /// The durable session id.
    public var storedSessionID: String?
    /// Stored id the session was resumed from.
    public var resumed: String?
    /// Session key (the stored id in this build).
    public var sessionKey: String?
    /// True when the server omitted the transcript.
    public var messagesOmitted: Bool?
    /// True while the transcript is still loading.
    public var hydrating: Bool?
    /// True when a turn is running.
    public var running: Bool?
    /// When the running turn started (Unix seconds).
    public var turnStartedAt: Double?
    /// When the session started (Unix seconds).
    public var startedAt: Double?
    /// Live status.
    public var status: LiveSessionStatus?
    /// The running turn so far, when there is one.
    public var inflight: InflightTurn?
    /// A prompt queued behind a busy session.
    public var queued: QueuedPrompt?
    /// An approval still waiting for an answer.
    public var pendingApproval: PendingApproval?
    /// Unanswered server requests.
    public var openRequests: [OpenRequestEntry]?
    /// A pending connection request. Kept raw.
    public var pendingConnection: JSONValue?
    /// Todo list state. Kept raw.
    public var todoState: JSONValue?
    /// Auto-continue state after an interrupt. Kept raw.
    public var autoContinue: JSONValue?

    enum CodingKeys: String, CodingKey {
        case info, messages, resumed, running, status, inflight, queued
        case sessionID = "session_id"
        case messageCount = "message_count"
        case storedSessionID = "stored_session_id"
        case sessionKey = "session_key"
        case messagesOmitted = "messages_omitted"
        case hydrating
        case turnStartedAt = "turn_started_at"
        case startedAt = "started_at"
        case pendingApproval = "pending_approval"
        case openRequests = "open_requests"
        case pendingConnection = "pending_connection"
        case todoState = "todo_state"
        case autoContinue = "auto_continue"
    }
}

/// Result of `session.create`.
public typealias SessionCreateResult = SessionAttachResult
/// Result of `session.resume`.
public typealias SessionResumeResult = SessionAttachResult
/// Result of `session.activate`.
public typealias SessionActivateResult = SessionAttachResult
