import Foundation

private struct Ack: Decodable, Sendable {}

private struct ActiveProfileBody: Encodable, Sendable { var name: String }

private struct CommentBody: Encodable, Sendable {
    var body: String
    var author: String?
}

private func items(_ pairs: KeyValuePairs<String, String?>) -> [URLQueryItem] {
    pairs.compactMap { pair in pair.value.map { URLQueryItem(name: pair.key, value: $0) } }
}

private func path(_ parts: String...) -> String {
    var allowed = CharacterSet.urlPathAllowed
    allowed.remove(charactersIn: "/")
    return parts.map { $0.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0 }.joined(separator: "/")
}

// MARK: - Server and account

extension RESTClient {
    /// `GET /api/health`. Works without a login.
    public func health() async throws -> ServerHealth { try await get("/api/health", scoped: false) }

    /// `GET /api/host/identity`.
    public func hostIdentity() async throws -> HostIdentity { try await get("/api/host/identity", scoped: false) }

    /// `GET /api/status`.
    public func status() async throws -> ServerStatus { try await get("/api/status", scoped: false) }

    /// `GET /api/auth/me`.
    public func currentUser() async throws -> AuthUser { try await get("/api/auth/me", scoped: false) }
}

// MARK: - Sessions

extension RESTClient {
    /// `GET /api/sessions`, newest first.
    public func sessions(limit: Int = 50, offset: Int = 0, archived: Bool = false) async throws -> SessionList {
        var query = [
            URLQueryItem(name: "limit", value: String(limit)), URLQueryItem(name: "offset", value: String(offset)),
        ]
        if archived { query.append(URLQueryItem(name: "archived", value: "true")) }
        return try await get("/api/sessions", query: query)
    }

    /// `GET /api/profiles/sessions`: recent sessions of every profile, each row tagged with its profile. Never scoped:
    /// the spec's `profile` query defaults to `all`, so the active profile would narrow the list. The contract gives no
    /// response schema, so the answer comes back as JSON.
    public func sessionsAcrossProfiles() async throws -> JSONValue {
        try await get("/api/profiles/sessions", scoped: false)
    }

    /// `GET /api/sessions/{id}`.
    public func session(id: String) async throws -> SessionRecord {
        try await get("/api/sessions/" + path(id))
    }

    /// `GET /api/sessions/{id}/messages`. With `oldest` false the first page holds the newest messages.
    public func messages(id: String, page: PageRequest = .init(), oldest: Bool = true) async throws -> MessagesPage {
        let query = page.queryItems + [URLQueryItem(name: "order", value: oldest ? "oldest" : "latest")]
        return try await get("/api/sessions/" + path(id, "messages"), query: query)
    }

    /// `GET /api/sessions/{id}/timeline`: the user turns, for jump-to and rewind.
    public func timeline(sessionID: String) async throws -> SessionTimeline {
        try await get("/api/sessions/" + path(sessionID, "timeline"))
    }

    /// `GET /api/sessions/search`.
    public func searchSessions(_ text: String, limit: Int = 30) async throws -> SessionSearchResults {
        try await get(
            "/api/sessions/search",
            query: [URLQueryItem(name: "q", value: text), URLQueryItem(name: "limit", value: String(limit))])
    }

    /// `GET /api/sessions/stats`.
    public func sessionStats() async throws -> SessionStats { try await get("/api/sessions/stats") }

    /// `PATCH /api/sessions/{id}`: rename, archive, pin or hide.
    public func updateSession(id: String, _ update: SessionUpdate) async throws {
        let _: Ack = try await send("PATCH", "/api/sessions/" + path(id), body: update)
    }

    /// `DELETE /api/sessions/{id}`. Cannot be undone.
    public func deleteSession(id: String) async throws {
        let _: Ack = try await send("DELETE", "/api/sessions/" + path(id))
    }
}

// MARK: - Profiles, models, skills, tools

extension RESTClient {
    /// `GET /api/profiles`.
    public func profiles() async throws -> [HermesProfile] {
        try await (get("/api/profiles", scoped: false) as ProfileList).profiles
    }

    /// `GET /api/profiles/active`.
    public func activeProfile() async throws -> ActiveProfile { try await get("/api/profiles/active", scoped: false) }

    /// `POST /api/profiles/active`: changes the server's default profile for all clients. Prefer
    /// ``RESTClient/setProfile(_:)`` to scope only this client.
    public func setActiveProfile(_ name: String) async throws {
        let _: Ack = try await send("POST", "/api/profiles/active", body: ActiveProfileBody(name: name), scoped: false)
    }

    /// `GET /api/model/info`.
    public func modelInfo() async throws -> ModelInfo { try await get("/api/model/info") }

    /// `GET /api/model/options`.
    public func modelOptions() async throws -> ModelOptions { try await get("/api/model/options") }

    /// `GET /api/skills`.
    public func skills() async throws -> [SkillInfo] { try await get("/api/skills") }

    /// `GET /api/tools/toolsets`.
    public func toolsets() async throws -> [ToolsetInfo] { try await get("/api/tools/toolsets") }
}

// MARK: - Kanban

extension RESTClient {
    /// `GET /api/plugins/kanban/board`. `board` is a slug from ``kanbanBoards()``; nil means the current board.
    public func kanbanBoard(_ board: String? = nil) async throws -> KanbanBoardView {
        try await get("/api/plugins/kanban/board", query: items(["board": board]))
    }

    /// `GET /api/plugins/kanban/boards`.
    public func kanbanBoards() async throws -> KanbanBoards { try await get("/api/plugins/kanban/boards") }

    /// `GET /api/plugins/kanban/tasks/{id}`.
    public func kanbanTask(id: String, board: String? = nil) async throws -> KanbanTaskDetail {
        try await get("/api/plugins/kanban/tasks/" + path(id), query: items(["board": board]))
    }

    /// `POST /api/plugins/kanban/tasks`.
    public func createKanbanTask(_ draft: KanbanTaskDraft, board: String? = nil) async throws -> KanbanTaskCreated {
        try await send("POST", "/api/plugins/kanban/tasks", query: items(["board": board]), body: draft)
    }

    /// `PATCH /api/plugins/kanban/tasks/{id}`. Throws ``RESTError/http(status:detail:)`` with `400` when the move is
    /// refused, for example `done` without a result.
    public func updateKanbanTask(id: String, _ update: KanbanTaskUpdate, board: String? = nil) async throws {
        let _: Ack = try await send(
            "PATCH", "/api/plugins/kanban/tasks/" + path(id), query: items(["board": board]), body: update)
    }

    /// `DELETE /api/plugins/kanban/tasks/{id}`.
    public func deleteKanbanTask(id: String, board: String? = nil) async throws {
        let _: Ack = try await send("DELETE", "/api/plugins/kanban/tasks/" + path(id), query: items(["board": board]))
    }

    /// `POST /api/plugins/kanban/tasks/{id}/comments`.
    public func addKanbanComment(id: String, text: String, author: String? = nil, board: String? = nil) async throws {
        let _: Ack = try await send(
            "POST", "/api/plugins/kanban/tasks/" + path(id, "comments"), query: items(["board": board]),
            body: CommentBody(body: text, author: author))
    }
}

// MARK: - Git

extension RESTClient {
    /// `GET /api/git/status?path=`: `path` is a directory on the server.
    public func gitStatus(path directory: String) async throws -> GitStatus {
        try await get("/api/git/status", query: [URLQueryItem(name: "path", value: directory)])
    }
}

extension RESTClient {
    /// `GET /api/auth/providers`: the interactive login providers. Public.
    public func authProviders() async throws -> [AuthProviderInfo] {
        let answer: AuthProvidersAnswer = try await get("/api/auth/providers", scoped: false)
        return answer.providers
    }

    /// `POST /auth/logout`: ends the cookie session. Best effort; the answer is a redirect.
    public func logout() async throws {
        do {
            _ = try await sendRaw("POST", "/auth/logout", scoped: false)
        } catch RESTError.http(let status, _) where (300..<400).contains(status) {
            // The server answers with a redirect to its login page.
        }
    }
}

/// One login provider from `GET /api/auth/providers`.
public struct AuthProviderInfo: Sendable, Equatable, Codable {
    /// Provider id, such as `basic`, `nous` or `self-hosted`.
    public var name: String
    /// Name to show.
    public var displayName: String?
    /// True for providers that sign in with a user name and password.
    public var supportsPassword: Bool?

    /// Creates a value.
    public init(name: String, displayName: String? = nil, supportsPassword: Bool? = nil) {
        self.name = name
        self.displayName = displayName
        self.supportsPassword = supportsPassword
    }
}

private struct AuthProvidersAnswer: Decodable, Sendable {
    var providers: [AuthProviderInfo]
}
