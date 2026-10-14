import Foundation

/// A kanban task. Only the fields the app reads are modelled.
public struct KanbanTask: Sendable, Equatable, Codable, Identifiable {
    /// Task id such as `t_55b18cdd`.
    public var id: String
    /// Title.
    public var title: String
    /// Longer description.
    public var body: String?
    /// Profile that works on it.
    public var assignee: String?
    /// `triage`, `todo`, `ready`, `running`, `blocked`, `done` or `archived`.
    public var status: String
    /// Higher runs first.
    public var priority: Int?
    /// Unix time created.
    public var createdAt: Int?
    /// Unix time started.
    public var startedAt: Int?
    /// Unix time completed.
    public var completedAt: Int?
    /// Result text.
    public var result: String?
    /// Session that worked on it.
    public var sessionId: String?
    /// Why it is blocked.
    public var blockKind: String?
    /// Failures in a row.
    public var consecutiveFailures: Int?
    /// Latest run summary.
    public var latestSummary: String?
}

/// One column of the board.
public struct KanbanColumn: Sendable, Equatable, Codable {
    /// Status name.
    public var name: String
    /// Tasks in it.
    public var tasks: [KanbanTask]
}

/// `GET /api/plugins/kanban/board`.
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

/// `GET /api/plugins/kanban/boards`.
public struct KanbanBoards: Sendable, Equatable, Codable {
    /// All boards.
    public var boards: [KanbanBoardInfo]
    /// Slug of the current one.
    public var current: String?
}

/// A comment on a task.
public struct KanbanComment: Sendable, Equatable, Codable {
    /// Comment text.
    public var body: String
    /// Author name.
    public var author: String?
    /// Unix time.
    public var createdAt: Int?
}

/// One entry of a task's history.
public struct KanbanEvent: Sendable, Equatable, Codable, Identifiable {
    /// Event id.
    public var id: Int
    /// Kind such as `created`, `claimed`, `completed`.
    public var kind: String
    /// Unix time.
    public var createdAt: Int?
    /// Event data.
    public var payload: JSONValue?
}

/// `GET /api/plugins/kanban/tasks/{id}`.
public struct KanbanTaskDetail: Sendable, Equatable, Codable {
    /// The task.
    public var task: KanbanTask
    /// Comments, oldest first.
    public var comments: [KanbanComment]?
    /// History.
    public var events: [KanbanEvent]?
}

/// `POST /api/plugins/kanban/tasks` answer.
public struct KanbanTaskCreated: Sendable, Equatable, Codable {
    /// The new task.
    public var task: KanbanTask
    /// Server warning such as a missing assignee, if any.
    public var warning: String?
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
