import Foundation
import HermesKit
import Testing

/// The `body` of an answer the recorder saved under Fixtures/rest. The recorder wraps each answer in an envelope that
/// also holds the request and the status. The client reads only the body.
func kanbanRecordedBody(_ name: String) throws -> String {
    let envelope = try #require(try JSONSerialization.jsonObject(with: Data(restFixture(name).utf8)) as? [String: Any])
    let body = try JSONSerialization.data(withJSONObject: try #require(envelope["body"]), options: [.fragmentsAllowed])
    return try #require(String(bytes: body, encoding: .utf8))
}

/// A JSON text read as an object. Tests compare each decoded value with the value in the same file, so no sample value
/// is pinned.
func kanbanJSONObject(_ text: String) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
}

/// The sorted keys of the request body the recorder sent with a write.
func kanbanRecordedRequestKeys(_ name: String) throws -> [String] {
    let envelope = try kanbanJSONObject(try restFixture(name))
    let request = try #require(envelope["request"] as? [String: Any])
    let body = try #require(request["body"] as? [String: Any])
    return body.keys.sorted()
}

@Suite struct KanbanReadTests {
    @Test func columnsKeepTheOrderTheServerSends() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"assignees":["ops"],"latest_event_id":7,"now":1791985341,"columns":[
              {"name":"done","tasks":[]},
              {"name":"triage","tasks":[{"id":"t_1","title":"Sort logs","status":"triage","priority":2,"assignee":"ops"}]},
              {"name":"blocked","tasks":[]}
            ]}
            """#)
        let board = try await makeClient(http).kanbanBoard("work")
        #expect(board.columns.map(\.name) == ["done", "triage", "blocked"])
        let card = try #require(board.columns[1].cards.first)
        #expect(card.id == "t_1" && card.title == "Sort logs")
        #expect(board.assignees == ["ops"] && board.latestEventId == 7)
        #expect(http.requests.first?.url.query == "board=work")
    }

    @Test func cardsReadOnlyIdAndTitleLeniently() async throws {
        // No recorded board has a card, so the card shape is unverified. The board still decodes, and each card keeps
        // only a string id and a string title.
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"""
            {"assignees":[],"latest_event_id":1,"now":1,"columns":[
              {"name":"ready","tasks":[
                {"id":"t_1","title":7,"extra":{"nested":[1,2]}},
                {"title":"no id"},
                "text",
                {"id":5,"title":"numeric id"},
                {"id":"t_2","title":"Second"}
              ]}
            ]}
            """#)
        let board = try await makeClient(http).kanbanBoard()
        let cards = try #require(board.columns.first).cards
        #expect(cards.map(\.id) == ["t_1", "t_2"])
        #expect(cards.map(\.title) == [nil, "Second"])
    }

    @Test func boardListDecodesTheRecordedAnswer() async throws {
        let name = "GET_api_plugins_kanban_boards"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let listing = try await makeClient(http).kanbanBoards()
        let raw = try kanbanJSONObject(try kanbanRecordedBody(name))
        let rawBoards = try #require(raw["boards"] as? [[String: Any]])
        let rawSlugs = rawBoards.compactMap { $0["slug"] as? String }
        #expect(listing.current == raw["current"] as? String)
        #expect(listing.boards.map(\.slug) == rawSlugs)
        let board = try #require(listing.boards.first)
        let rawBoard = try #require(rawBoards.first)
        #expect(board.name == rawBoard["name"] as? String)
        #expect(board.description == rawBoard["description"] as? String)
        #expect(board.isCurrent == rawBoard["is_current"] as? Bool)
        #expect(board.archived == rawBoard["archived"] as? Bool)
        #expect(board.total == rawBoard["total"] as? Int)
    }

    @Test func boardDecodesTheRecordedColumnsInOrder() async throws {
        let name = "GET_api_plugins_kanban_board"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let board = try await makeClient(http).kanbanBoard()
        let raw = try kanbanJSONObject(try kanbanRecordedBody(name))
        let rawColumns = try #require(raw["columns"] as? [[String: Any]])
        let rawNames = rawColumns.compactMap { $0["name"] as? String }
        #expect(board.columns.map(\.name) == rawNames)
        #expect(board.assignees == raw["assignees"] as? [String])
        #expect(board.latestEventId == raw["latest_event_id"] as? Int)
        #expect(board.now == raw["now"] as? Int)
        #expect(http.requests.first?.url.query == nil)
    }

    @Test func taskDetailDecodesTheRecordedTaskAndHistory() async throws {
        let name = "GET_api_plugins_kanban_tasks_task_id"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let detail = try await makeClient(http).kanbanTask(id: "t_fixture", board: "recorder")
        let raw = try kanbanJSONObject(try kanbanRecordedBody(name))
        let rawTask = try #require(raw["task"] as? [String: Any])
        let task = detail.task
        #expect(task.id == rawTask["id"] as? String)
        #expect(task.title == rawTask["title"] as? String)
        #expect(task.body == rawTask["body"] as? String)
        #expect(task.status == rawTask["status"] as? String)
        #expect(task.assignee == rawTask["assignee"] as? String)
        #expect(task.priority == rawTask["priority"] as? Int)
        #expect(task.consecutiveFailures == rawTask["consecutive_failures"] as? Int)
        #expect(task.createdAt == rawTask["created_at"] as? Int)
        let rawEvent = try #require((raw["events"] as? [[String: Any]])?.first)
        let event = try #require(detail.events?.first)
        #expect(event.id == rawEvent["id"] as? Int)
        #expect(event.kind == rawEvent["kind"] as? String)
        #expect(event.createdAt == rawEvent["created_at"] as? Int)
        #expect((event.payload != nil) == (rawEvent["payload"] is [String: Any]))
        #expect(http.requests.first?.url.query == "board=recorder")
    }

    @Test func createdTaskDecodesTheRecordedAnswer() async throws {
        let name = "POST_api_plugins_kanban_tasks"
        let http = FakeHTTP()
        http.enqueue(200, try kanbanRecordedBody(name))
        let draft = KanbanTaskDraft(title: "recorder task", body: "recorder fixture")
        let created = try await makeClient(http).createKanbanTask(draft, board: "recorder")
        let raw = try kanbanJSONObject(try kanbanRecordedBody(name))
        let rawTask = try #require(raw["task"] as? [String: Any])
        #expect(created.task.id == rawTask["id"] as? String)
        #expect(created.task.title == rawTask["title"] as? String)
        #expect(created.warning == raw["warning"] as? String)
        #expect(http.requests.first?.url.query == "board=recorder")
    }

    @Test func handCopiedAnswersFillTheAssigneeAndTheWarning() async throws {
        // The recorded task answers have a null assignee and no warning in this run. The two hand-copied files are
        // the samples where both are set, so each decoded value is checked against its own file.
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("kanban_task_detail"))
        http.enqueue(200, try restFixture("kanban_task_created"))
        let client = makeClient(http)
        let detail = try await client.kanbanTask(id: "t_fixture")
        let created = try await client.createKanbanTask(KanbanTaskDraft(title: "Second", assignee: "default"))
        let rawDetail = try kanbanJSONObject(try restFixture("kanban_task_detail"))
        let rawTask = try #require(rawDetail["task"] as? [String: Any])
        let rawCreated = try kanbanJSONObject(try restFixture("kanban_task_created"))
        #expect(detail.task.assignee != nil && detail.task.assignee == rawTask["assignee"] as? String)
        #expect(created.warning != nil && created.warning == rawCreated["warning"] as? String)
    }

    @Test func aWrongTypeInAssigneeOrWarningDoesNotFailTheAnswer() async throws {
        let http = FakeHTTP()
        http.enqueue(
            200,
            #"{"task":{"id":"t_1","title":"x","status":"ready","assignee":{"name":"ops"}},"events":[]}"#)
        http.enqueue(
            200,
            #"{"task":{"id":"t_2","title":"y","status":"todo","assignee":["ops"]},"warning":5}"#)
        let client = makeClient(http)
        let detail = try await client.kanbanTask(id: "t_1")
        #expect(detail.task.id == "t_1" && detail.task.assignee == nil)
        let created = try await client.createKanbanTask(KanbanTaskDraft(title: "y"))
        #expect(created.task.id == "t_2" && created.task.assignee == nil && created.warning == nil)
    }

    @Test func untypedReadsReturnTheirAnswer() async throws {
        let http = FakeHTTP()
        for _ in 0..<2 { http.enqueue(200, #"{"ready":{"count":2},"oldest_ready_age_seconds":90}"#) }
        let client = makeClient(http)
        let stats = try await client.kanbanStats(board: "work")
        #expect(stats == .object(["ready": .object(["count": 2]), "oldest_ready_age_seconds": 90]))
        _ = try await client.kanbanStats()
        let paths = http.requests.map { ($0.url.path(percentEncoded: true), $0.url.query) }
        #expect(paths[0].0 == "/api/plugins/kanban/stats" && paths[0].1 == "board=work")
        #expect(paths[1].1 == nil)
    }

    @Test func everyUntypedReadUsesItsPathAndQuery() async throws {
        let http = FakeHTTP()
        for _ in 0..<9 { http.enqueue(200, #"{"ok":true}"#) }
        let client = makeClient(http, profile: "ops")
        _ = try await client.kanbanConfig()
        _ = try await client.kanbanAssignees(board: "work")
        _ = try await client.kanbanProfiles()
        _ = try await client.kanbanActiveWorkers(board: "work")
        _ = try await client.kanbanDiagnostics(board: "work", severity: "error")
        _ = try await client.kanbanTaskLog(id: "t 1", tail: 200, board: "work")
        _ = try await client.kanbanRun(id: 9, board: "work")
        _ = try await client.kanbanDiagnostics()
        _ = try await client.kanbanTaskLog(id: "t_2")
        let requests = http.requests
        #expect(requests.allSatisfy { $0.method == "GET" })
        #expect(
            requests.map { $0.url.path(percentEncoded: true) } == [
                "/api/plugins/kanban/config", "/api/plugins/kanban/assignees", "/api/plugins/kanban/profiles",
                "/api/plugins/kanban/workers/active", "/api/plugins/kanban/diagnostics",
                "/api/plugins/kanban/tasks/t%201/log", "/api/plugins/kanban/runs/9",
                "/api/plugins/kanban/diagnostics",
                "/api/plugins/kanban/tasks/t_2/log",
            ])
        #expect(
            requests.map(\.url.query) == [
                "profile=ops", "board=work&profile=ops", "profile=ops", "board=work&profile=ops",
                "board=work&severity=error&profile=ops", "tail=200&board=work&profile=ops", "board=work&profile=ops",
                "profile=ops", "profile=ops",
            ])
    }
}
