import Foundation
import HermesKit
import Testing

/// Each test serves a recorded testbed response and checks the request the facade built and the decoded values.
@Suite struct RESTEndpointTests {
    private func run<T: Sendable>(
        _ fixture: String, profile: String? = nil, _ call: (RESTClient) async throws -> T
    ) async throws -> (T, HTTPRequest) {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture(fixture))
        let client = makeClient(http, profile: profile)
        let value = try await call(client)
        return (value, try #require(http.requests.first))
    }

    @Test func healthStatusIdentityAndUser() async throws {
        let (health, healthRequest) = try await run("health") { try await $0.health() }
        #expect(health.ok && health.displayVersion == "git.d97007c" && health.authRequired == true)
        #expect(healthRequest.url.path == "/api/health" && healthRequest.url.query == nil)
        let (identity, _) = try await run("host_identity") { try await $0.hostIdentity() }
        #expect(identity.ok && identity.role == "serve" && identity.protocolVersion != nil)
        let (status, _) = try await run("status") { try await $0.status() }
        #expect(status.releaseDate == "2026.9.24" && status.authProviders == ["basic"] && status.profiles?.count == 2)
        let (user, _) = try await run("auth_me") { try await $0.currentUser() }
        #expect(user.userId == "tester" && user.provider == "basic")
    }

    @Test func sessionList() async throws {
        let (list, request) = try await run("sessions", profile: "ops") { try await $0.sessions(limit: 3, offset: 6) }
        #expect(list.sessions.count == 3 && list.total >= 3)
        let first = try #require(list.sessions.first)
        #expect(first.id.hasPrefix("2026") && first.source == "tui" && first.model == "fake-model")
        #expect(first.messageCount != nil && first.startedAt != nil && first.cwd == "/opt/hermes")
        #expect(request.url.query == "limit=3&offset=6&profile=ops")
    }

    @Test func sessionDetailEncodesTheIDInThePath() async throws {
        let (detail, request) = try await run("session_detail") { try await $0.session(id: "a/b c") }
        #expect(
            detail.id == "20261014_032737_07e33f" && detail.profile == "default" && detail.archived == false
                && detail.pinned == false)
        #expect(request.url.path == "/api/sessions/a%2Fb%20c")
    }

    @Test func messagesTimelineSearchStats() async throws {
        let (page, request) = try await run("session_messages") {
            try await $0.messages(id: "s1", page: PageRequest(limit: 3))
        }
        #expect(page.messages.count == 3 && page.messages.first?.role == "user" && page.pagination?.returned == 6)
        #expect(page.messages.allSatisfy { $0.id > 0 && $0.messageUid != nil })
        #expect(request.url.query == "limit=3&offset=0&order=oldest")
        let (timeline, _) = try await run("session_timeline") { try await $0.timeline(sessionID: "s1") }
        #expect(timeline.entries.first?.id == timeline.entries.first?.rowId)
        let (hits, searchRequest) = try await run("session_search") { try await $0.searchSessions("hello world") }
        #expect(hits.results.count == 3 && hits.results.first?.snippet?.contains(">>>") == true)
        #expect(searchRequest.url.query?.hasPrefix("q=hello%20world&limit=30") == true)
        let (stats, _) = try await run("session_stats") { try await $0.sessionStats() }
        #expect(stats.total > 0 && stats.bySource?["tui"] != nil)
    }

    @Test func profilesModelsSkillsToolsets() async throws {
        let (profiles, profilesRequest) = try await run("profiles", profile: "ops") { try await $0.profiles() }
        #expect(profiles.map(\.name).contains("default") && profiles.first { $0.isDefault == true } != nil)
        #expect(profilesRequest.url.query == nil, "profile list is never profile-scoped")
        let (active, _) = try await run("profile_active") { try await $0.activeProfile() }
        #expect(active.active == "default")
        let (info, _) = try await run("model_info") { try await $0.modelInfo() }
        #expect(info.model == "fake-model" && info.effectiveContextLength != nil)
        let (options, _) = try await run("model_options") { try await $0.modelOptions() }
        #expect(options.providers.first?.models == ["fake-model"] && options.providers.first?.isCurrent == true)
        let (skills, _) = try await run("skills") { try await $0.skills() }
        #expect(skills.count == 3 && skills.first?.name == "claude-code")
        let (toolsets, _) = try await run("toolsets") { try await $0.toolsets() }
        #expect(toolsets.count == 3 && toolsets.first?.tools?.isEmpty == false)
    }

    @Test func kanbanReadAndCreate() async throws {
        let (board, boardRequest) = try await run("kanban_board") { try await $0.kanbanBoard("work") }
        #expect(board.columns.first?.name == "triage" && board.columns.count == 8)
        #expect(boardRequest.url.query == "board=work")
        let (boards, _) = try await run("kanban_boards") { try await $0.kanbanBoards() }
        #expect(boards.current == "default" && boards.boards.first?.slug == "default")
        let (detail, _) = try await run("kanban_task_detail") { try await $0.kanbanTask(id: "t_2cc67aea") }
        #expect(
            detail.task.title == "Second" && detail.task.status == "ready" && detail.events?.first?.kind == "created")
        let draft = KanbanTaskDraft(title: "Second", body: "b", assignee: "default")
        let (created, request) = try await run("kanban_task_created") { try await $0.createKanbanTask(draft) }
        #expect(created.task.assignee == "default")
        #expect(request.method == "POST")
        let body = try #require(request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["title"] as? String == "Second" && body["priority"] == nil)
    }

    @Test func kanbanWritesUseSnakeCaseBodies() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"deleted":true,"task_id":"t_1"}"#)
        let client = makeClient(http)
        try await client.updateKanbanTask(
            id: "t_1", KanbanTaskUpdate(status: "blocked", blockReason: "waiting"), board: "work")
        try await client.addKanbanComment(id: "t_1", text: "hi", author: "jt")
        try await client.deleteKanbanTask(id: "t_1")
        let requests = http.requests
        #expect(requests.map(\.method) == ["PATCH", "POST", "DELETE"])
        #expect(requests[0].url.query == "board=work")
        #expect(requests[1].url.path == "/api/plugins/kanban/tasks/t_1/comments")
        let patch = try #require(
            requests[0].body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(patch["block_reason"] as? String == "waiting" && patch["blockReason"] == nil)
    }

    @Test func sessionWritesAndRefusedMove() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, #"{"deleted":true}"#)
        http.enqueue(400, #"{"detail":"completion blocked: t_1 has no result or summary evidence"}"#)
        let client = makeClient(http)
        try await client.updateSession(id: "s1", SessionUpdate(title: "New", pinned: true))
        try await client.deleteSession(id: "s1")
        await #expect(
            throws: RESTError.http(status: 400, detail: "completion blocked: t_1 has no result or summary evidence")
        ) {
            try await client.updateKanbanTask(id: "t_1", KanbanTaskUpdate(status: "done"))
        }
        let sent = try #require(
            http.requests.first?.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(sent["title"] as? String == "New" && sent["pinned"] as? Bool == true && sent["archived"] == nil)
        #expect(http.requests[1].method == "DELETE")
    }

    @Test func gitStatus() async throws {
        let (status, request) = try await run("git_status") { try await $0.gitStatus(path: "/opt/hermes") }
        #expect(status.files?.first?.path == "testbed-entrypoints/" && status.files?.first?.untracked == true)
        #expect(request.url.query == "path=/opt/hermes")
    }
}
