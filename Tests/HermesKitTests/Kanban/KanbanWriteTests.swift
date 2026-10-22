import Foundation
import HermesKit
import Testing

/// The JSON object a request sent, for checking snake_case keys and which keys were left out.
private func sentObject(_ request: HTTPRequest?) throws -> [String: Any] {
    let body = try #require(request?.body)
    return try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
}

/// Decodes what a request sent with the same key rules the app uses to read answers.
private func decodeSent<Value: Decodable>(_ type: Value.Type, _ request: HTTPRequest?) throws -> Value {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(type, from: try #require(request?.body))
}

@Suite struct KanbanBoardWriteTests {
    @Test func createBoardSendsSnakeCaseAndLeavesOutNilFields() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        let draft = KanbanBoardDraft(slug: "home", name: "Home", defaultWorkdir: "/srv/home")
        try await makeClient(http).createKanbanBoard(draft)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/boards")
        #expect(request.url.query == nil)
        let body = try sentObject(request)
        #expect(body["slug"] as? String == "home" && body["name"] as? String == "Home")
        #expect(body["default_workdir"] as? String == "/srv/home")
        #expect(body["description"] == nil && body["project_id"] == nil && body["switch"] == nil)
        #expect(try decodeSent(KanbanBoardDraft.self, request) == draft)
    }

    @Test func createBoardCanAlsoSwitchToIt() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        let draft = KanbanBoardDraft(slug: "ops", switchToBoard: true)
        try await makeClient(http).createKanbanBoard(draft)
        let request = try #require(http.requests.first)
        #expect(try sentObject(request)["switch"] as? Bool == true)
        #expect(try decodeSent(KanbanBoardDraft.self, request) == draft)
    }

    @Test func createBoardSendsTheRecordedKeys() async throws {
        let name = "POST_api_plugins_kanban_boards"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let draft = KanbanBoardDraft(slug: "recorder", name: "recorder", switchToBoard: false)
        try await makeClient(http).createKanbanBoard(draft)
        let request = try #require(http.requests.first)
        let recordedKeys = try kanbanRecordedRequestKeys(name)
        #expect(try sentObject(request).keys.sorted() == recordedKeys)
        #expect(request.url.query == nil)
    }

    @Test func renameSendsOnlyTheChangedFieldsAndEncodesTheSlug() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        let update = KanbanBoardUpdate(name: "Home jobs", projectId: "p_1")
        try await makeClient(http).updateKanbanBoard(slug: "my board", update)
        let request = try #require(http.requests.first)
        #expect(request.method == "PATCH" && request.url.path == "/api/plugins/kanban/boards/my%20board")
        let body = try sentObject(request)
        #expect(body.keys.sorted() == ["name", "project_id"])
        #expect(body["project_id"] as? String == "p_1")
        #expect(try decodeSent(KanbanBoardUpdate.self, request) == update)
    }

    @Test func deleteArchivesUnlessHardIsAsked() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        http.enqueue(200, "{}")
        let client = makeClient(http)
        try await client.deleteKanbanBoard(slug: "work")
        try await client.deleteKanbanBoard(slug: "work", hard: true)
        let requests = http.requests
        #expect(requests.map(\.method) == ["DELETE", "DELETE"])
        #expect(requests.map(\.url.path) == ["/api/plugins/kanban/boards/work", "/api/plugins/kanban/boards/work"])
        #expect(requests[0].url.query == nil)
        #expect(requests[1].url.query == "delete=true")
    }

    @Test func recordedHardDeleteSendsTheRecordedQuery() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody("DELETE_api_plugins_kanban_boards_recorder"))
        try await makeClient(http).deleteKanbanBoard(slug: "recorder", hard: true)
        let request = try #require(http.requests.first)
        #expect(request.method == "DELETE" && request.url.path == "/api/plugins/kanban/boards/recorder")
        #expect(request.url.query == "delete=true")
        #expect(request.body == nil)
    }

    @Test func switchPostsToTheBoardWithNoBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        try await makeClient(http).switchKanbanBoard(slug: "work")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/boards/work/switch")
        #expect(request.body == nil)
    }
}

@Suite struct KanbanTaskWriteTests {
    @Test func bulkMoveSendsIDsAndStatusOnly() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"results":[{"id":"t_1","ok":true}]}"#)
        let change = KanbanBulkChange(ids: ["t_1", "t_2"], status: "ready")
        try await makeClient(http).bulkUpdateKanbanTasks(change, board: "work")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/tasks/bulk")
        #expect(request.url.query == "board=work")
        let body = try sentObject(request)
        #expect(body.keys.sorted() == ["ids", "status"])
        #expect((body["ids"] as? [String]) == ["t_1", "t_2"] && body["status"] as? String == "ready")
        #expect(try decodeSent(KanbanBulkChange.self, request) == change)
    }

    @Test func bulkCarriesCompletionEvidenceAndReclaim() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        let change = KanbanBulkChange(
            ids: ["t_1"], status: "done", archive: false, result: "shipped", summary: "done", reclaimFirst: true)
        try await makeClient(http).bulkUpdateKanbanTasks(change)
        let request = try #require(http.requests.first)
        let body = try sentObject(request)
        #expect(body["result"] as? String == "shipped" && body["summary"] as? String == "done")
        #expect(body["reclaim_first"] as? Bool == true && body["archive"] as? Bool == false)
        #expect(request.url.query == nil)
        #expect(try decodeSent(KanbanBulkChange.self, request) == change)
    }

    @Test func aRefusedBulkMoveThrowsTheServerDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(400, #"{"detail":"completion blocked: t_1 has no result or summary evidence"}"#)
        await #expect(
            throws: RESTError.http(
                status: 400, detail: "completion blocked: t_1 has no result or summary evidence")
        ) {
            try await makeClient(http).bulkUpdateKanbanTasks(KanbanBulkChange(ids: ["t_1"], status: "done"))
        }
    }

    @Test func reclaimSendsAnEmptyBodyOrTheReason() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        http.enqueue(200, "{}")
        let client = makeClient(http)
        try await client.reclaimKanbanTask(id: "t_1")
        try await client.reclaimKanbanTask(id: "t 2", reason: "stuck", board: "work")
        let requests = http.requests
        #expect(requests[0].url.path == "/api/plugins/kanban/tasks/t_1/reclaim")
        #expect(try sentObject(requests[0]).isEmpty)
        #expect(requests[1].url.path == "/api/plugins/kanban/tasks/t%202/reclaim")
        #expect(requests[1].url.query == "board=work")
        #expect(try sentObject(requests[1])["reason"] as? String == "stuck")
    }

    @Test func reassignSendsTheProfileAndKeepsReclaimOffByDefault() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        http.enqueue(200, "{}")
        let client = makeClient(http)
        try await client.reassignKanbanTask(id: "t_1", to: "ops", board: "work")
        try await client.reassignKanbanTask(id: "t_1", to: "default", reclaimFirst: true, reason: "load")
        let requests = http.requests
        #expect(requests.map(\.url.path) == Array(repeating: "/api/plugins/kanban/tasks/t_1/reassign", count: 2))
        #expect(requests[0].url.query == "board=work")
        let first = try sentObject(requests[0])
        #expect(first["profile"] as? String == "ops" && first["reclaim_first"] as? Bool == false)
        #expect(first["reason"] == nil)
        let second = try sentObject(requests[1])
        #expect(second["profile"] as? String == "default" && second["reclaim_first"] as? Bool == true)
        #expect(second["reason"] as? String == "load")
    }

    @Test func specifySendsAnEmptyBodyAndReadsOnlyTheStatus() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":false,"reason":"no auxiliary model configured"}"#)
        try await makeClient(http).specifyKanbanTask(id: "t_3", board: "work")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/tasks/t_3/specify")
        #expect(request.url.query == "board=work")
        #expect(try sentObject(request).isEmpty)
    }

    @Test func aWriteReadsOnlyTheStatus() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "", headers: ["Content-Type": "application/octet-stream"])
        try await makeClient(http).reclaimKanbanTask(id: "t_1")
        #expect(http.requests.count == 1)
    }

    @Test func dispatchSendsItsOptionsAsQuery() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"dispatched":0}"#)
        http.enqueue(200, #"{"dispatched":0}"#)
        let client = makeClient(http)
        try await client.dispatchKanban(board: "work", dryRun: true, maxTasks: 3)
        try await client.dispatchKanban()
        let requests = http.requests
        #expect(requests.allSatisfy { $0.method == "POST" && $0.body == nil })
        #expect(requests.allSatisfy { $0.url.path == "/api/plugins/kanban/dispatch" })
        #expect(requests[0].url.query == "board=work&dry_run=true&max=3")
        #expect(requests[1].url.query == nil)
    }

    @Test func recordedTaskCreateSendsTheRecordedKeys() async throws {
        let name = "POST_api_plugins_kanban_tasks"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let draft = KanbanTaskDraft(title: "recorder task", body: "recorder fixture")
        _ = try await makeClient(http).createKanbanTask(draft, board: "recorder")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/tasks")
        #expect(request.url.query == "board=recorder")
        let recordedKeys = try kanbanRecordedRequestKeys(name)
        #expect(try sentObject(request).keys.sorted() == recordedKeys)
    }

    @Test func recordedCommentSendsTheRecordedKeysAndReadsOnlyTheStatus() async throws {
        let name = "POST_api_plugins_kanban_tasks_task_id_comments"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        try await makeClient(http).addKanbanComment(
            id: "t_fixture", text: "recorder comment", author: "recorder", board: "recorder")
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/plugins/kanban/tasks/t_fixture/comments")
        #expect(request.url.query == "board=recorder")
        let recordedKeys = try kanbanRecordedRequestKeys(name)
        #expect(try sentObject(request).keys.sorted() == recordedKeys)
    }

    @Test func recordedTaskUpdateSendsTheRecordedKeys() async throws {
        let name = "PATCH_api_plugins_kanban_tasks_task_id"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        try await makeClient(http).updateKanbanTask(
            id: "t_fixture", KanbanTaskUpdate(status: "todo"), board: "recorder")
        let request = try #require(http.requests.first)
        #expect(request.method == "PATCH" && request.url.path == "/api/plugins/kanban/tasks/t_fixture")
        #expect(request.url.query == "board=recorder")
        let recordedKeys = try kanbanRecordedRequestKeys(name)
        #expect(try sentObject(request).keys.sorted() == recordedKeys)
    }

    @Test func recordedTaskDeleteSendsTheRecordedRequest() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody("DELETE_api_plugins_kanban_tasks_task_id"))
        try await makeClient(http).deleteKanbanTask(id: "t_fixture", board: "recorder")
        let request = try #require(http.requests.first)
        #expect(request.method == "DELETE" && request.url.path == "/api/plugins/kanban/tasks/t_fixture")
        #expect(request.url.query == "board=recorder")
        #expect(request.body == nil)
    }
}
