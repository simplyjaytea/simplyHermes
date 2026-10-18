import Foundation
import HermesKit
import Testing

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
        let task = try #require(board.columns[1].tasks.first)
        #expect(task.id == "t_1" && task.title == "Sort logs" && task.priority == 2 && task.assignee == "ops")
        #expect(board.assignees == ["ops"] && board.latestEventId == 7)
        #expect(http.requests.first?.url.query == "board=work")
    }

    @Test func boardsAndTaskDetailDecodeTheRecordedShapes() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("kanban_boards"))
        http.enqueue(200, try restFixture("kanban_task_detail"))
        let client = makeClient(http)
        let boards = try await client.kanbanBoards()
        #expect(boards.current == "default" && boards.boards.first?.isCurrent == true)
        let detail = try await client.kanbanTask(id: "t_2cc67aea", board: "work")
        #expect(detail.task.priority == 0 && detail.task.status == "ready" && detail.comments?.isEmpty == true)
        #expect(http.requests.last?.url.query == "board=work")
    }

    @Test func untypedReadsReturnTheirAnswer() async throws {
        let http = FakeHTTP()
        for _ in 0..<2 { http.enqueue(200, #"{"ready":{"count":2},"oldest_ready_age_seconds":90}"#) }
        let client = makeClient(http)
        let stats = try await client.kanbanStats(board: "work")
        #expect(stats == .object(["ready": .object(["count": 2]), "oldest_ready_age_seconds": 90]))
        _ = try await client.kanbanStats()
        let paths = http.requests.map { ($0.url.path, $0.url.query) }
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
        _ = try await client.kanbanRun(id: "r_9", board: "work")
        _ = try await client.kanbanDiagnostics()
        _ = try await client.kanbanTaskLog(id: "t_2")
        let requests = http.requests
        #expect(requests.allSatisfy { $0.method == "GET" })
        #expect(
            requests.map(\.url.path) == [
                "/api/plugins/kanban/config", "/api/plugins/kanban/assignees", "/api/plugins/kanban/profiles",
                "/api/plugins/kanban/workers/active", "/api/plugins/kanban/diagnostics",
                "/api/plugins/kanban/tasks/t%201/log", "/api/plugins/kanban/runs/r_9",
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
