import Foundation

/// Body of `POST /api/plugins/kanban/boards`. Only `slug` is required; nil fields are left out of the request.
public struct KanbanBoardDraft: Sendable, Equatable, Codable {
    /// Slug used in `?board=`. Creating a slug that exists returns that board.
    public var slug: String
    /// Name to show.
    public var name: String?
    /// Description.
    public var description: String?
    /// Icon name.
    public var icon: String?
    /// Color name.
    public var color: String?
    /// Working directory on the server for new tasks.
    public var defaultWorkdir: String?
    /// Project to scope the board to.
    public var projectId: String?
    /// Also makes the board the server's current one. Other clients and the CLI follow it.
    public var switchToBoard: Bool?

    /// Creates a draft.
    public init(
        slug: String, name: String? = nil, description: String? = nil, icon: String? = nil, color: String? = nil,
        defaultWorkdir: String? = nil, projectId: String? = nil, switchToBoard: Bool? = nil
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.defaultWorkdir = defaultWorkdir
        self.projectId = projectId
        self.switchToBoard = switchToBoard
    }

    private enum CodingKeys: String, CodingKey {
        case slug, name, description, icon, color, defaultWorkdir, projectId
        case switchToBoard = "switch"
    }
}

/// Body of `PATCH /api/plugins/kanban/boards/{slug}`. Nil fields stay unchanged. The slug cannot change.
public struct KanbanBoardUpdate: Sendable, Equatable, Codable {
    /// New name.
    public var name: String?
    /// New description.
    public var description: String?
    /// New icon name.
    public var icon: String?
    /// New color name.
    public var color: String?
    /// New working directory on the server.
    public var defaultWorkdir: String?
    /// New project scope.
    public var projectId: String?

    /// Creates an update.
    public init(
        name: String? = nil, description: String? = nil, icon: String? = nil, color: String? = nil,
        defaultWorkdir: String? = nil, projectId: String? = nil
    ) {
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.defaultWorkdir = defaultWorkdir
        self.projectId = projectId
    }
}

/// Body of `POST /api/plugins/kanban/tasks/bulk`: one change applied to every id. Nil fields are not sent.
/// A move is a `status` change. The server answers each id on its own, so one id can fail while the others succeed.
public struct KanbanBulkChange: Sendable, Equatable, Codable {
    /// Task ids to change.
    public var ids: [String]
    /// New status, which is the column to move to.
    public var status: String?
    /// New assignee profile.
    public var assignee: String?
    /// New priority, higher first.
    public var priority: Int?
    /// True archives the tasks.
    public var archive: Bool?
    /// Completion result. Moving to `done` needs a result or a summary.
    public var result: String?
    /// Completion summary.
    public var summary: String?
    /// Stops the running worker first when the change needs it.
    public var reclaimFirst: Bool?

    /// Creates a change for `ids`.
    public init(
        ids: [String], status: String? = nil, assignee: String? = nil, priority: Int? = nil, archive: Bool? = nil,
        result: String? = nil, summary: String? = nil, reclaimFirst: Bool? = nil
    ) {
        self.ids = ids
        self.status = status
        self.assignee = assignee
        self.priority = priority
        self.archive = archive
        self.result = result
        self.summary = summary
        self.reclaimFirst = reclaimFirst
    }
}
