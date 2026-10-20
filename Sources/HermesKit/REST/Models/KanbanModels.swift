import Foundation

/// A kanban task. Only the fields the app reads are modelled. Each one is shown by the `task` object in
/// Fixtures/rest/GET_api_plugins_kanban_tasks_task_id.json, except `assignee`: see its doc. Not modelled, because every
/// recorded task answer has them null: `started_at`, `completed_at`, `result`, `session_id`, `block_kind` and
/// `latest_summary`.
public struct KanbanTask: Sendable, Equatable, Codable, Identifiable {
    /// Task id. Opaque: never parse it.
    public var id: String
    /// Title.
    public var title: String
    /// Longer description.
    public var body: String?
    /// Profile that works on it. Needs real server [JT]: only the hand-copied
    /// Fixtures/rest/kanban_task_detail.json sets it. A value of another type reads as nil.
    public var assignee: String?
    /// Status name, as the server sends it. The board's columns list the statuses in use.
    public var status: String
    /// Higher runs first.
    public var priority: Int?
    /// Unix time created.
    public var createdAt: Int?
    /// Failures in a row.
    public var consecutiveFailures: Int?

    private enum CodingKeys: String, CodingKey {
        case id, title, body, assignee, status, priority, createdAt, consecutiveFailures
    }

    /// Reads the fields as the synthesized decoder did, except `assignee`: a value of another type reads as nil instead
    /// of failing the task.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assignee = try? container.decodeIfPresent(String.self, forKey: .assignee)
        status = try container.decode(String.self, forKey: .status)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        consecutiveFailures = try container.decodeIfPresent(Int.self, forKey: .consecutiveFailures)
    }
}

/// One column of the board. Shape: Fixtures/rest/GET_api_plugins_kanban_board.json, which gives the column name.
/// Every recorded `tasks` list is empty, so no file shows a card. Cards stay ``JSONValue``. ``cards`` reads only `id`
/// and `title`, leniently. The board's task contents are unverified: needs real server [JT].
public struct KanbanColumn: Sendable, Equatable, Codable {
    /// Status name.
    public var name: String
    /// The cards as the server sends them. Read them through ``cards``.
    public var tasks: [JSONValue]

    /// The cards with a string `id`, read as ``KanbanCard``.
    public var cards: [KanbanCard] { tasks.compactMap { KanbanCard($0) } }
}

/// A card in a column, read leniently: only `id` and `title`. A card without a string `id` is left out of
/// ``KanbanColumn/cards``, and a `title` that is not a string reads as nil. Unverified: needs real server [JT].
public struct KanbanCard: Sendable, Equatable, Identifiable {
    /// Task id. Opaque.
    public let id: String
    /// Title, when the card holds a string under `title`.
    public let title: String?

    /// Makes a card from its parts.
    public init(id: String, title: String?) {
        self.id = id
        self.title = title
    }

    /// Reads `id` and `title` from one card. Nil when the card is not an object with a string `id`.
    public init?(_ card: JSONValue) {
        guard case .object(let fields) = card, case .string(let id)? = fields["id"] else { return nil }
        self.id = id
        if case .string(let title)? = fields["title"] {
            self.title = title
        } else {
            self.title = nil
        }
    }
}

/// `GET /api/plugins/kanban/board`. Shape: Fixtures/rest/GET_api_plugins_kanban_board.json.
public struct KanbanBoardView: Sendable, Equatable, Codable {
    /// The columns, in display order.
    public var columns: [KanbanColumn]
    /// Profiles tasks can be assigned to.
    public var assignees: [String]?
    /// Newest event id, for polling.
    public var latestEventId: Int?
    /// Server time (Unix seconds).
    public var now: Int?
}

/// One board from `GET /api/plugins/kanban/boards`.
/// Shape: one entry in Fixtures/rest/GET_api_plugins_kanban_boards.json.
public struct KanbanBoardInfo: Sendable, Equatable, Codable, Identifiable {
    /// Slug used in `?board=`.
    public var slug: String
    /// Name to show.
    public var name: String
    /// Description.
    public var description: String?
    /// True for the board in use.
    public var isCurrent: Bool?
    /// True when archived.
    public var archived: Bool?
    /// Tasks on it.
    public var total: Int?
    /// Identity for lists.
    public var id: String { slug }
}

/// `GET /api/plugins/kanban/boards`. Shape: Fixtures/rest/GET_api_plugins_kanban_boards.json.
public struct KanbanBoards: Sendable, Equatable, Codable {
    /// All boards.
    public var boards: [KanbanBoardInfo]
    /// Slug of the current one.
    public var current: String?
}

/// One entry of a task's history.
/// Shape: an entry of `events` in Fixtures/rest/GET_api_plugins_kanban_tasks_task_id.json.
public struct KanbanEvent: Sendable, Equatable, Codable, Identifiable {
    /// Event id.
    public var id: Int
    /// Kind, as the server sends it.
    public var kind: String
    /// Unix time.
    public var createdAt: Int?
    /// Event data.
    public var payload: JSONValue?
}

/// `GET /api/plugins/kanban/tasks/{id}`. Shape: Fixtures/rest/GET_api_plugins_kanban_tasks_task_id.json.
/// `comments` is not typed: the recording has only an empty list, and the comment write answers `{"ok": true}`.
public struct KanbanTaskDetail: Sendable, Equatable, Codable {
    /// The task.
    public var task: KanbanTask
    /// History.
    public var events: [KanbanEvent]?
}

/// `POST /api/plugins/kanban/tasks` answer. Shape: `task` in Fixtures/rest/POST_api_plugins_kanban_tasks.json.
/// `warning` is only in the hand-copied Fixtures/rest/kanban_task_created.json; the recorded create had none.
public struct KanbanTaskCreated: Sendable, Equatable, Codable {
    /// The new task.
    public var task: KanbanTask
    /// Server warning such as a missing assignee, if any. Needs real server [JT]. A value of another type reads as nil,
    /// so the create still succeeds.
    public var warning: String?

    private enum CodingKeys: String, CodingKey {
        case task, warning
    }

    /// Reads `task` as usual. `warning` reads as nil when it is not a string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(KanbanTask.self, forKey: .task)
        warning = try? container.decodeIfPresent(String.self, forKey: .warning)
    }
}

/// Body of `POST /api/plugins/kanban/tasks`.
public struct KanbanTaskDraft: Sendable, Equatable, Codable {
    /// Title.
    public var title: String
    /// Description.
    public var body: String?
    /// Profile to work on it.
    public var assignee: String?
    /// Priority, higher first.
    public var priority: Int?
    /// Put it in triage so the server specifies it first.
    public var triage: Bool?

    /// Creates a draft.
    public init(title: String, body: String? = nil, assignee: String? = nil, priority: Int? = nil) {
        self.title = title
        self.body = body
        self.assignee = assignee
        self.priority = priority
    }
}

/// Body of `PATCH /api/plugins/kanban/tasks/{id}`. Nil fields stay unchanged.
/// Moving a task to `done` needs `result` or `summary`; the server answers `400` otherwise.
public struct KanbanTaskUpdate: Sendable, Equatable, Codable {
    /// New status.
    public var status: String?
    /// New assignee.
    public var assignee: String?
    /// New priority.
    public var priority: Int?
    /// New title.
    public var title: String?
    /// New description.
    public var body: String?
    /// Completion result.
    public var result: String?
    /// Completion summary.
    public var summary: String?
    /// Reason when blocking.
    public var blockReason: String?

    /// Creates an update.
    public init(
        status: String? = nil, assignee: String? = nil, priority: Int? = nil, title: String? = nil, body: String? = nil,
        result: String? = nil, summary: String? = nil, blockReason: String? = nil
    ) {
        self.status = status
        self.assignee = assignee
        self.priority = priority
        self.title = title
        self.body = body
        self.result = result
        self.summary = summary
        self.blockReason = blockReason
    }
}
