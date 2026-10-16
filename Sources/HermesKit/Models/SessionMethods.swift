/// Params that name one session: `session.history`, `session.status`, `session.usage`, `subagent.list`.
public struct SessionParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates params for one session.
    public init(sessionID: String, profile: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
    }
}

/// Params of `session.history`.
public typealias SessionHistoryParams = SessionParams
/// Params of `session.status`.
public typealias SessionStatusParams = SessionParams
/// Params of `session.usage`.
public typealias SessionUsageParams = SessionParams
/// Params of `subagent.list`.
public typealias SubagentListParams = SessionParams

/// Params of `session.create`. Every field is optional; an empty value encodes as `{}`.
public struct SessionCreateParams: Sendable, Equatable, Codable {
    /// Profile to create the session under.
    public var profile: String?
    /// Terminal width in columns.
    public var cols: Int?
    /// Where the session came from.
    public var source: String?
    /// Working directory on the server.
    public var cwd: String?
    /// True when `cwd` was chosen by the user.
    public var cwdExplicit: Bool?
    /// Messages to seed the transcript with.
    public var messages: [SeedMessage]?
    /// Parent session, for a branch.
    public var parentSessionID: String?
    /// Title to set.
    public var title: String?
    /// Model to use.
    public var model: String?
    /// Provider to use.
    public var provider: String?
    /// Reasoning effort to use.
    public var reasoningEffort: String?
    /// Whether fast mode is on.
    public var fast: Bool?
    /// Service tier to use.
    public var serviceTier: String?
    /// Stop the session when the socket closes.
    public var closeOnDisconnect: Bool?
    /// Keep the session out of session lists.
    public var hidden: Bool?
    /// Internal flag for group rooms.
    public var roomPlumbing: Bool?
    /// Follow the profile's configuration instead of a pinned model.
    public var followProfileConfig: Bool?
    /// Key that makes a retried create return the same session.
    public var idempotencyKey: String?

    /// Creates params. Pass only the fields you need.
    public init(
        profile: String? = nil, cols: Int? = nil, source: String? = nil, cwd: String? = nil,
        cwdExplicit: Bool? = nil, messages: [SeedMessage]? = nil, parentSessionID: String? = nil,
        title: String? = nil, model: String? = nil, provider: String? = nil, reasoningEffort: String? = nil,
        fast: Bool? = nil, serviceTier: String? = nil, closeOnDisconnect: Bool? = nil, hidden: Bool? = nil,
        roomPlumbing: Bool? = nil, followProfileConfig: Bool? = nil, idempotencyKey: String? = nil
    ) {
        self.profile = profile
        self.cols = cols
        self.source = source
        self.cwd = cwd
        self.cwdExplicit = cwdExplicit
        self.messages = messages
        self.parentSessionID = parentSessionID
        self.title = title
        self.model = model
        self.provider = provider
        self.reasoningEffort = reasoningEffort
        self.fast = fast
        self.serviceTier = serviceTier
        self.closeOnDisconnect = closeOnDisconnect
        self.hidden = hidden
        self.roomPlumbing = roomPlumbing
        self.followProfileConfig = followProfileConfig
        self.idempotencyKey = idempotencyKey
    }

    enum CodingKeys: String, CodingKey {
        case profile, cols, source, cwd, messages, title, model, provider, fast, hidden
        case cwdExplicit = "cwd_explicit"
        case parentSessionID = "parent_session_id"
        case reasoningEffort = "reasoning_effort"
        case serviceTier = "service_tier"
        case closeOnDisconnect = "close_on_disconnect"
        case roomPlumbing = "room_plumbing"
        case followProfileConfig = "follow_profile_config"
        case idempotencyKey = "idempotency_key"
    }
}

/// Params of `session.resume`. Pass the stored session id as `sessionID`.
public struct SessionResumeParams: Sendable, Equatable, Codable {
    /// The stored (durable) session id.
    public var sessionID: String
    /// Profile to resume under.
    public var profile: String?
    /// Terminal width in columns.
    public var cols: Int?
    /// Where the request came from.
    public var source: String?
    /// Attach without loading the full session.
    public var lazy: Bool?
    /// Load the transcript later.
    public var deferHistory: Bool?
    /// Skip the transcript in the result.
    public var omitMessages: Bool?
    /// Build the agent eagerly.
    public var eagerBuild: Bool?
    /// Stop the session when the socket closes.
    public var closeOnDisconnect: Bool?
    /// Return images inline.
    public var inlineImages: Bool?

    /// Creates params for a stored session id.
    public init(
        sessionID: String, profile: String? = nil, cols: Int? = nil, source: String? = nil, lazy: Bool? = nil,
        deferHistory: Bool? = nil, omitMessages: Bool? = nil, eagerBuild: Bool? = nil,
        closeOnDisconnect: Bool? = nil, inlineImages: Bool? = nil
    ) {
        self.sessionID = sessionID
        self.profile = profile
        self.cols = cols
        self.source = source
        self.lazy = lazy
        self.deferHistory = deferHistory
        self.omitMessages = omitMessages
        self.eagerBuild = eagerBuild
        self.closeOnDisconnect = closeOnDisconnect
        self.inlineImages = inlineImages
    }

    enum CodingKeys: String, CodingKey {
        case profile, cols, source, lazy
        case sessionID = "session_id"
        case deferHistory = "defer_history"
        case omitMessages = "omit_messages"
        case eagerBuild = "eager_build"
        case closeOnDisconnect = "close_on_disconnect"
        case inlineImages = "inline_images"
    }
}

/// Params of `session.activate`. Pass the live session id as `sessionID`.
public struct SessionActivateParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// Terminal width in columns.
    public var cols: Int?
    /// Skip the transcript in the result.
    public var omitMessages: Bool?

    /// Creates params for a live session id.
    public init(sessionID: String, profile: String? = nil, cols: Int? = nil, omitMessages: Bool? = nil) {
        self.sessionID = sessionID
        self.profile = profile
        self.cols = cols
        self.omitMessages = omitMessages
    }

    enum CodingKeys: String, CodingKey {
        case profile, cols
        case sessionID = "session_id"
        case omitMessages = "omit_messages"
    }
}

/// Params of `session.list`.
public struct SessionListParams: Sendable, Equatable, Codable {
    /// Profile to list.
    public var profile: String?
    /// Filter by title.
    public var title: String?
    /// Maximum rows.
    public var limit: Int?
    /// Include hidden sessions.
    public var includeHidden: Bool?

    /// Creates list params.
    public init(profile: String? = nil, title: String? = nil, limit: Int? = nil, includeHidden: Bool? = nil) {
        self.profile = profile
        self.title = title
        self.limit = limit
        self.includeHidden = includeHidden
    }

    enum CodingKeys: String, CodingKey {
        case profile, title, limit
        case includeHidden = "include_hidden"
    }
}

/// Result of `session.list`.
public struct SessionListResult: Sendable, Equatable, Codable {
    /// Stored sessions, newest first.
    public var sessions: [SessionListRow]
}

/// One stored session in `session.list`.
public struct SessionListRow: Sendable, Equatable, Codable {
    /// Session id.
    public var id: String
    /// Id this session resolves to, when it was merged.
    public var resolvedID: String?
    /// Title.
    public var title: String?
    /// First line of the conversation.
    public var preview: String?
    /// When the session started (Unix seconds).
    public var startedAt: Double?
    /// Messages stored.
    public var messageCount: Int?
    /// Messages in the live session.
    public var liveMessageCount: Int?
    /// Where the session came from, for example `tui`.
    public var source: String?
    /// Id of the root session of this lineage.
    public var lineageRootID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, preview, source
        case resolvedID = "resolved_id"
        case startedAt = "started_at"
        case messageCount = "message_count"
        case liveMessageCount = "live_message_count"
        case lineageRootID = "_lineage_root_id"
    }
}

/// Params of `session.active_list`.
public struct SessionActiveListParams: Sendable, Equatable, Codable {
    /// Profile to list.
    public var profile: String?
    /// The session the caller is on, so the list can mark it `current`.
    public var currentSessionID: String?

    /// Creates list params.
    public init(profile: String? = nil, currentSessionID: String? = nil) {
        self.profile = profile
        self.currentSessionID = currentSessionID
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case currentSessionID = "current_session_id"
    }
}

/// Result of `session.active_list`.
public struct SessionActiveListResult: Sendable, Equatable, Codable {
    /// Live sessions on the server.
    public var sessions: [SessionActiveItem]
}

/// One live session in `session.active_list`.
public struct SessionActiveItem: Sendable, Equatable, Codable {
    /// True for the session the caller named as current.
    public var current: Bool
    /// Live session id.
    public var id: String
    /// Last activity (Unix seconds).
    public var lastActive: Double
    /// Messages in the session.
    public var messageCount: Int
    /// Model name.
    public var model: String
    /// First line of the conversation.
    public var preview: String
    /// Durable session id.
    public var sessionKey: String
    /// When the session started (Unix seconds).
    public var startedAt: Double
    /// Live status.
    public var status: LiveSessionStatus
    /// Title.
    public var title: String

    enum CodingKeys: String, CodingKey {
        case current, id, model, preview, status, title
        case lastActive = "last_active"
        case messageCount = "message_count"
        case sessionKey = "session_key"
        case startedAt = "started_at"
    }
}

/// Result of `session.history`.
public struct SessionHistoryResult: Sendable, Equatable, Codable {
    /// Number of messages.
    public var count: Int
    /// The transcript, oldest first.
    public var messages: [TranscriptMessage]
}

/// Result of `session.status`.
public struct SessionStatusResult: Sendable, Equatable, Codable {
    /// Human-readable status text.
    public var output: String
}

/// Params of `session.interrupt`.
public struct SessionInterruptParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// Task id the interrupt is meant for, when a hosted task is involved.
    public var expectedHostedTaskID: String?

    /// Creates params for a live session id.
    public init(sessionID: String, profile: String? = nil, expectedHostedTaskID: String? = nil) {
        self.sessionID = sessionID
        self.profile = profile
        self.expectedHostedTaskID = expectedHostedTaskID
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
        case expectedHostedTaskID = "expected_hosted_task_id"
    }
}

/// Result of `session.interrupt`. The `message.complete` for the turn follows it.
public struct SessionInterruptResult: Sendable, Equatable, Codable {
    /// Whether a running turn was interrupted.
    public var status: InterruptStatus
    /// Same information as a boolean, when sent.
    public var interrupted: Bool?
    /// Whether turn isolation applied, when sent.
    public var turnIsolation: Bool?

    enum CodingKeys: String, CodingKey {
        case status, interrupted
        case turnIsolation = "turn_isolation"
    }
}

/// Params of `session.events.since`: replay the events after `lastSeen`.
public struct SessionEventsSinceParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// Last `seq` the client has. Nil asks for the ring from the start.
    public var lastSeen: Int?

    /// Creates replay params.
    public init(sessionID: String, profile: String? = nil, lastSeen: Int? = nil) {
        self.sessionID = sessionID
        self.profile = profile
        self.lastSeen = lastSeen
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
        case lastSeen = "last_seen"
    }
}

/// Result of `session.events.since`. The ring keeps the last 512 events per session.
public struct SessionEventsSinceResult: Sendable, Equatable, Codable {
    /// The replayed events, in order.
    public var events: [GatewayEventEnvelope]
    /// Highest `seq` in the ring. Advance the watermark to this when `truncated` is true.
    public var latestSeq: Int
    /// True when the ring overflowed: the gap cannot be replayed, so re-read the history.
    public var truncated: Bool
    /// Number of events returned.
    public var count: Int
    /// Server process id. Compare with `gateway.ready.replay_epoch`.
    public var epoch: String
    /// Server requests still waiting for an answer.
    public var openRequests: [OpenRequestEntry]

    enum CodingKeys: String, CodingKey {
        case events, count, epoch, truncated
        case latestSeq = "latest_seq"
        case openRequests = "open_requests"
    }
}

/// Params of `approval.respond`. Any socket may answer; the first answer wins.
public struct ApprovalRespondParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The answer.
    public var choice: ApprovalChoice?
    /// Apply the answer to every pending approval.
    public var all: Bool?
    /// Id of the approval request (`request_id` of the `approval` request).
    public var requestID: String?

    /// Creates an approval answer.
    public init(
        sessionID: String, profile: String? = nil, choice: ApprovalChoice? = nil, all: Bool? = nil,
        requestID: String? = nil
    ) {
        self.sessionID = sessionID
        self.profile = profile
        self.choice = choice
        self.all = all
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case profile, choice, all
        case sessionID = "session_id"
        case requestID = "request_id"
    }
}

/// Result of `approval.respond`.
public struct ApprovalRespondResult: Sendable, Equatable, Codable {
    /// How many approvals this answer resolved.
    public var resolved: Int
}

/// Params of `session.steer`: text that joins the next tool result without interrupting the turn.
public struct SessionSteerParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// The text to inject.
    public var text: String
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates params for a live session id.
    public init(sessionID: String, text: String, profile: String? = nil) {
        self.sessionID = sessionID
        self.text = text
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile, text
        case sessionID = "session_id"
    }
}
