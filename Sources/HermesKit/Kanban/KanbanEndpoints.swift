import Foundation

// The schema leaves most kanban answers untyped (`{}`). Those calls return the answer as ``JSONValue``. Typed calls
// stay in `REST/RESTEndpoints.swift` and `REST/Models/KanbanModels.swift`.

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

/// Keeps a JSON answer when the server sent one. Answers that are empty or not JSON give nil.
private func kanbanAnswer(_ response: HTTPResponse) -> JSONValue? {
    try? JSONDecoder().decode(JSONValue.self, from: response.body)
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
            query: kanbanQuery(["tail": tail.map { String($0) }, "board": board]))
    }

    /// `GET /api/plugins/kanban/runs/{id}`: one run, under `run`.
    public func kanbanRun(id: String, board: String? = nil) async throws -> JSONValue {
        try await get("/api/plugins/kanban/runs/" + kanbanSegment(id), query: kanbanQuery(["board": board]))
    }

    // MARK: Boards

    /// `POST /api/plugins/kanban/boards`. A slug that exists already returns that board.
    public func createKanbanBoard(_ draft: KanbanBoardDraft) async throws {
        let _: HTTPResponse = try await send("POST", "/api/plugins/kanban/boards", body: draft)
    }

    /// `PATCH /api/plugins/kanban/boards/{slug}`: display metadata, working directory and project. The slug stays.
    public func updateKanbanBoard(slug: String, _ update: KanbanBoardUpdate) async throws {
        let _: HTTPResponse = try await send(
            "PATCH", "/api/plugins/kanban/boards/" + kanbanSegment(slug), body: update)
    }

    /// `DELETE /api/plugins/kanban/boards/{slug}`. Archives the board unless `hard` is true, which deletes it.
    public func deleteKanbanBoard(slug: String, hard: Bool = false) async throws {
        let query = hard ? [URLQueryItem(name: "delete", value: "true")] : []
        let _: HTTPResponse = try await send(
            "DELETE", "/api/plugins/kanban/boards/" + kanbanSegment(slug), query: query)
    }

    /// `POST /api/plugins/kanban/boards/{slug}/switch`: makes the board the server's current one for every client.
    public func switchKanbanBoard(slug: String) async throws {
        let _: HTTPResponse = try await send("POST", "/api/plugins/kanban/boards/" + kanbanSegment(slug) + "/switch")
    }

    // MARK: Tasks

    /// `POST /api/plugins/kanban/tasks/bulk`. Returns the server's per-id answer when it sends JSON.
    /// A refused move throws ``RESTError/http(status:detail:)``.
    public func bulkUpdateKanbanTasks(_ change: KanbanBulkChange, board: String? = nil) async throws -> JSONValue? {
        let response: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/bulk", query: kanbanQuery(["board": board]), body: change)
        return kanbanAnswer(response)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/reclaim`: releases the active worker's claim now instead of at the claim
    /// timeout. The running worker is stopped.
    public func reclaimKanbanTask(id: String, reason: String? = nil, board: String? = nil) async throws -> JSONValue? {
        let response: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/reclaim",
            query: kanbanQuery(["board": board]), body: KanbanReclaimBody(reason: reason))
        return kanbanAnswer(response)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/reassign`: gives the task to `profile`, optionally reclaiming it first.
    public func reassignKanbanTask(
        id: String, to profile: String, reclaimFirst: Bool = false, reason: String? = nil, board: String? = nil
    ) async throws -> JSONValue? {
        let response: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/reassign",
            query: kanbanQuery(["board": board]),
            body: KanbanReassignBody(profile: profile, reclaimFirst: reclaimFirst, reason: reason))
        return kanbanAnswer(response)
    }

    /// `POST /api/plugins/kanban/tasks/{id}/specify`: fleshes out a triage task with the auxiliary model. A refusal
    /// comes back in the answer, not as an HTTP error.
    public func specifyKanbanTask(id: String, author: String? = nil, board: String? = nil) async throws -> JSONValue? {
        let response: HTTPResponse = try await send(
            "POST", "/api/plugins/kanban/tasks/" + kanbanSegment(id) + "/specify",
            query: kanbanQuery(["board": board]), body: KanbanSpecifyBody(author: author))
        return kanbanAnswer(response)
    }

    /// `POST /api/plugins/kanban/dispatch`: starts ready tasks now instead of at the next dispatcher tick.
    /// `dryRun` only reports what would start. `maxTasks` caps the count (the server default is 8).
    public func dispatchKanban(board: String? = nil, dryRun: Bool = false, maxTasks: Int? = nil) async throws
        -> JSONValue?
    {
        let query = kanbanQuery([
            "board": board, "dry_run": dryRun ? "true" : nil, "max": maxTasks.map { String($0) },
        ])
        let response: HTTPResponse = try await send("POST", "/api/plugins/kanban/dispatch", query: query)
        return kanbanAnswer(response)
    }
}
