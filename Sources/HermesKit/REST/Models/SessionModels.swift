import Foundation

/// A flag the server stores as an integer: it sends `0` or `1` for some and `true` or `false` for others.
public struct LooseBool: Sendable, Equatable, Codable, ExpressibleByBooleanLiteral {
    /// The flag.
    public var value: Bool

    /// Creates a flag.
    public init(_ value: Bool) { self.value = value }

    /// Creates a flag from `true` or `false`.
    public init(booleanLiteral value: Bool) { self.value = value }

    /// Decodes a boolean or a number (non-zero is true).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let flag = try? container.decode(Bool.self) {
            value = flag
        } else {
            value = try container.decode(Int.self) != 0
        }
    }

    /// Encodes as a boolean.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

/// A stored session, as listed by `GET /api/sessions` and returned in full by `GET /api/sessions/{id}`.
/// The list omits `title` for sessions that have none yet; the detail adds `systemPrompt` and the flags.
public struct SessionRecord: Sendable, Equatable, Codable, Identifiable {
    /// Stored session id such as `20261014_032737_07e33f`.
    public var id: String
    /// Where it started: `tui`, `cli`, a messaging platform.
    public var source: String?
    /// Title, once generated.
    public var title: String?
    /// Model used.
    public var model: String?
    /// Session this one branched from, such as a subagent's parent.
    public var parentSessionId: String?
    /// Unix time of the first message.
    public var startedAt: Double?
    /// Unix time it ended, if it did.
    public var endedAt: Double?
    /// Why it ended, such as `ws_orphan_reap`.
    public var endReason: String?
    /// Messages stored.
    public var messageCount: Int?
    /// Tool calls made.
    public var toolCallCount: Int?
    /// Prompt tokens.
    public var inputTokens: Int?
    /// Completion tokens.
    public var outputTokens: Int?
    /// Working directory.
    public var cwd: String?
    /// Git branch of the working directory.
    public var gitBranch: String?
    /// Git root of the working directory.
    public var gitRepoRoot: String?
    /// Estimated cost in US dollars.
    public var estimatedCostUsd: Double?
    /// Unix time of the last activity.
    public var lastActivityAt: Double?
    /// Detail only: archived flag.
    public var archived: LooseBool?
    /// Detail only: pinned flag.
    public var pinned: LooseBool?
    /// Detail only: hidden flag.
    public var hidden: LooseBool?
    /// Detail only: profile it belongs to.
    public var profile: String?
}

/// `GET /api/sessions`.
public struct SessionList: Sendable, Equatable, Codable {
    /// The page of sessions.
    public var sessions: [SessionRecord]
    /// Total sessions matching.
    public var total: Int
    /// Page size used.
    public var limit: Int?
    /// Offset used.
    public var offset: Int?
}

/// `GET /api/sessions/stats`.
public struct SessionStats: Sendable, Equatable, Codable {
    /// All sessions.
    public var total: Int
    /// Sessions in the live store.
    public var activeStore: Int?
    /// Archived sessions.
    public var archived: Int?
    /// Messages stored.
    public var messages: Int?
    /// Session count per source.
    public var bySource: [String: Int]?
}

/// One stored message from `GET /api/sessions/{id}/messages`.
public struct StoredMessage: Sendable, Equatable, Codable, Identifiable {
    /// Row id. Use it to cut or rewind (`prompt.submit` truncation needs the row id).
    public var id: Int
    /// Owning session.
    public var sessionId: String
    /// `user`, `assistant`, `tool` or `system`.
    public var role: String
    /// Text content. Tool messages carry their output here.
    public var content: String?
    /// Id of the tool call a `tool` message answers.
    public var toolCallId: String?
    /// Tool calls an `assistant` message made.
    public var toolCalls: JSONValue?
    /// Tool name for a `tool` message.
    public var toolName: String?
    /// Unix time.
    public var timestamp: Double?
    /// Why generation stopped.
    public var finishReason: String?
    /// Reasoning text, when the model gave it.
    public var reasoning: String?
    /// Display hint such as `cron`.
    public var displayKind: String?
    /// Stable id across rewrites.
    public var messageUid: String?
}

/// Paging info in a message or timeline page.
public struct PageInfo: Sendable, Equatable, Codable {
    /// Page size used.
    public var limit: Int?
    /// Offset used.
    public var offset: Int?
    /// `latest` or `oldest`.
    public var order: String?
    /// Rows returned.
    public var returned: Int?
}

/// `GET /api/sessions/{id}/messages`.
public struct MessagesPage: Sendable, Equatable, Codable {
    /// Session id.
    public var sessionId: String
    /// Profile that holds it.
    public var profile: String?
    /// The messages.
    public var messages: [StoredMessage]
    /// Paging.
    public var pagination: PageInfo?
}

/// One user turn in `GET /api/sessions/{id}/timeline`.
public struct TimelineEntry: Sendable, Equatable, Codable, Identifiable {
    /// Row id of the user message.
    public var rowId: Int
    /// First words of the turn.
    public var preview: String
    /// Unix time.
    public var timestamp: Double?
    /// Identity for lists.
    public var id: Int { rowId }
}

/// `GET /api/sessions/{id}/timeline`.
public struct SessionTimeline: Sendable, Equatable, Codable {
    /// Session id.
    public var sessionId: String
    /// The turns.
    public var entries: [TimelineEntry]
}

/// One hit of `GET /api/sessions/search`.
public struct SessionSearchHit: Sendable, Equatable, Codable, Identifiable {
    /// Session id.
    public var sessionId: String
    /// Match with the hit wrapped in `>>>` and `<<<`.
    public var snippet: String?
    /// Role of the matching message.
    public var role: String?
    /// Session title.
    public var title: String?
    /// Source of the session.
    public var source: String?
    /// Model used.
    public var model: String?
    /// Unix time of the last activity.
    public var lastActive: Double?
    /// First words of the session.
    public var preview: String?
    /// Identity for lists.
    public var id: String { sessionId }
}

/// `GET /api/sessions/search`.
public struct SessionSearchResults: Sendable, Equatable, Codable {
    /// The hits.
    public var results: [SessionSearchHit]
}

/// Body of `PATCH /api/sessions/{id}`. Nil fields stay unchanged.
public struct SessionUpdate: Sendable, Equatable, Codable {
    /// New title.
    public var title: String?
    /// Archive or restore.
    public var archived: Bool?
    /// Hide or show.
    public var hidden: Bool?
    /// Pin or unpin.
    public var pinned: Bool?
    /// Mark unread.
    public var unread: Bool?

    /// Creates an update.
    public init(
        title: String? = nil, archived: Bool? = nil, hidden: Bool? = nil, pinned: Bool? = nil, unread: Bool? = nil
    ) {
        self.title = title
        self.archived = archived
        self.hidden = hidden
        self.pinned = pinned
        self.unread = unread
    }
}

/// Page size and offset for list calls.
public struct PageRequest: Sendable, Equatable {
    /// Rows per page.
    public var limit: Int
    /// Rows to skip.
    public var offset: Int

    /// Creates a page request.
    public init(limit: Int = 100, offset: Int = 0) {
        self.limit = limit
        self.offset = offset
    }

    var queryItems: [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset))]
    }
}
