import Foundation

// Reads whose answers the recorder did not type return ``JSONValue``. Writes return nothing: the caller checks the
// status and reloads from the server. Typed calls stay in `REST/RESTEndpoints.swift` and
// `REST/Models/KanbanModels.swift`.

private struct KanbanReclaimBody: Encodable, Sendable {
    var reason: String?
}

private struct KanbanReassignBody: Encodable, Sendable {
    var profile: String?
    var reclaimFirst: Bool
    var reason: String?
}

private struct KanbanSpecifyBody: Encodable, Sendable {
    var author: String?
}

private func kanbanQuery(_ pairs: KeyValuePairs<String, String?>) -> [URLQueryItem] {
    pairs.compactMap { pair in pair.value.map { URLQueryItem(name: pair.key, value: $0) } }
}

/// One path segment, percent-encoded. Slashes inside the value are encoded too.
private func kanbanSegment(_ value: String) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
}

extension RESTClient {
    // MARK: Reads

    /// `GET /api/plugins/kanban/config`: the dashboard's kanban preferences. Also the presence check.
    public func kanbanConfig() async throws -> JSONValue {
        try await get("/api/plugins/kanban/config")
    }

    /// `GET /api/plugins/kanban/stats`: counts per status and per assignee, and the age of the oldest ready task.
    public func kanbanStats(board: String? = nil) async throws -> JSONValue {
        try await get("/api/plugins/kanban/stats", query: kanbanQuery(["board": board]))
    }

    /// `GET /api/plugins/kanban/assignees`: the profiles that can take tasks on this board.
    public func kanbanAssignees(board: String? = nil) async throws -> JSONValue {
        try await get("/api/plugins/kanban/assignees", query: kanbanQuery(["board": board]))
    }

    /// `GET /api/plugins/kanban/profiles`: every installed profile with its kanban description.
    public func kanbanProfiles() async throws -> JSONValue {
        try await get("/api/plugins/kanban/profiles")
    }

    /// `GET /api/plugins/kanban/workers/active`: the running workers, as `{workers, count, checked_at}`.
    public func kanbanActiveWorkers(board: String? = nil) async throws -> JSONValue {
        try await get("/api/plugins/kanban/workers/active", query: kanbanQuery(["board": board]))
    }

    /// `GET /api/plugins/kanban/diagnostics`: tasks with an active diagnostic. `severity` is `warning`, `error` or
    /// `critical`.
    public func kanbanDiagnostics(board: String? = nil, severity: String? = nil) async throws -> JSONValue {
        try await get(
            "/api/plugins/kanban/diagnostics", query: kanbanQuery(["board": board, "severity": severity]))
    }

    /// `GET /api/plugins/kanban/tasks/{id}/log`: the worker's output. `tail` caps the bytes returned.
    public func kanbanTaskLog(id: String, tail: Int? = nil, board: String? = nil) async throws -> JSONValue {
        try await get(
            "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/log",
            query: kanbanQuery(["tail": tail.map { String($0) }, "board": board]), encodedPath: true)
    }

    /// `GET /api/plugins/kanban/runs/{id}`: one run, under `run`. Not recorded: the testbed never dispatches, so no run
    /// id exists.
    public func kanbanRun(id: Int, board: String? = nil) async throws -> JSONValue {
        try await get("/api/plugins/kanban/runs/" + String(id), query: kanbanQuery(["board": board]))
    }

    // MARK: Boards

    /// `POST /api/plugins/kanban/boards`. Reads only the status.
    public func createKanbanBoard(_ draft: KanbanBoardDraft) async throws {
        let _: HTTPResponse = try await send("POST", "/api/plugins/kanban/boards", body: draft)
    }

    /// `PATCH /api/plugins/kanban/boards/{slug}`: display metadata, working directory and project. The slug stays.
    /// Not recorded on the testbed.
    public func updateKanbanBoard(slug: String, _ update: KanbanBoardUpdate) async throws {
        let _: HTTPResponse = try await send(
            "PATCH", "/api/plugins/kanban/boards/" + kanbanSegment(slug), body: update, encodedPath: true)
    }

    /// `DELETE /api/plugins/kanban/boards/{slug}`. Archives the board unless `hard` is true, which deletes it.
    /// The hard delete is recorded on the testbed. Archiving is not.
    public func deleteKanbanBoard(slug: String, hard: Bool = false) async throws {
        let query = hard ? [URLQueryItem(name: "delete", value: "true")] : []
        let _: HTTPResponse = try await send(
            "DELETE", "/api/plugins/kanban/boards/" + kanbanSegment(slug), query: query, encodedPath: true)
    }

    /// `POST /api/plugins/kanban/boards/{slug}/switch`: makes the board the server's current one for every client.
    /// Not recorded on the testbed.
    public func switchKanbanBoard(slug: String) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/boards/" + kanbanSegment(slug) + "/switch", encodedPath: true)
    }

    // MARK: Tasks

    /// `POST /api/plugins/kanban/tasks/bulk`: one change applied to every id. Not recorded on the testbed. The answer
    /// is not read, so reload the board to see the result. A refused move throws ``RESTError/http(status:detail:)``.
    public func bulkUpdateKanbanTasks(_ change: KanbanBulkChange, board: String? = nil) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/bulk", query: kanbanQuery(["board": board]), body: change)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/reclaim`: releases the active worker's claim now instead of at the claim
    /// timeout. The running worker is stopped. Not recorded on the testbed; reload the task to see the result.
    public func reclaimKanbanTask(id: String, reason: String? = nil, board: String? = nil) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/reclaim",
            query: kanbanQuery(["board": board]), body: KanbanReclaimBody(reason: reason), encodedPath: true)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/reassign`: gives the task to `profile`, optionally reclaiming it first.
    /// Not recorded on the testbed; reload the task to see the result.
    public func reassignKanbanTask(
        id: String, to profile: String, reclaimFirst: Bool = false, reason: String? = nil, board: String? = nil
    ) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/reassign",
            query: kanbanQuery(["board": board]),
            body: KanbanReassignBody(profile: profile, reclaimFirst: reclaimFirst, reason: reason), encodedPath: true)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/specify`: fleshes out a triage task with the auxiliary model. Not recorded
    /// on the testbed. The answer is not read, so reload the task to see the result.
    public func specifyKanbanTask(id: String, author: String? = nil, board: String? = nil) async throws {
        let _: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/specify",
            query: kanbanQuery(["board": board]), body: KanbanSpecifyBody(author: author), encodedPath: true)
    }

    /// `POST /api/plugins/kanban/dispatch`: starts ready tasks now instead of at the next dispatcher tick.
    /// Not recorded: the testbed forbids dispatch. `dryRun` only reports what would start. `maxTasks` caps the count,
    /// and the server default is 8.
    public func dispatchKanban(board: String? = nil, dryRun: Bool = false, maxTasks: Int? = nil) async throws {
        let query = kanbanQuery([
            "board": board, "dry_run": dryRun ? "true" : nil, "max": maxTasks.map { String($0) },
        ])
        let _: HTTPResponse = try await send("POST", "/api/plugins/kanban/dispatch", query: query)
    }
}
