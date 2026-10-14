import Foundation
import HermesKit
import Testing

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set (for example `http://127.0.0.1:9119`):
/// `testbed/scripts/up.sh && HERMES_TESTBED_URL=http://127.0.0.1:9119 swift test --filter RESTLiveTests`.
/// Without the variable the test passes without doing anything.
@Suite struct RESTLiveTests {
    @Test func loginThenReadEveryEndpointGroup() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let client = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())

        await #expect(throws: RESTError.unauthorized) { _ = try await client.currentUser() }
        try await client.passwordLogin(username: "tester", password: "testbed-password")
        #expect(try await client.currentUser().userId == "tester")
        #expect(try await client.health().ok)
        #expect(try await client.hostIdentity().role == "serve")
        #expect(try await client.status().releaseDate != nil)

        let ticket = try await client.webSocketTicket()
        #expect(ticket.ttlSeconds == 30 && ticket.ticket.count > 20)

        let sessions = try await client.sessions(limit: 5)
        if let first = sessions.sessions.first {
            #expect(try await client.session(id: first.id).id == first.id)
            _ = try await client.messages(id: first.id, page: PageRequest(limit: 5))
            _ = try await client.timeline(sessionID: first.id)
        }
        _ = try await client.searchSessions("hello")
        _ = try await client.sessionStats()
        #expect(try await client.profiles().contains { $0.name == "default" })
        _ = try await client.activeProfile()
        #expect(try await client.modelInfo().model.isEmpty == false)
        #expect(try await client.modelOptions().providers.isEmpty == false)
        #expect(try await client.skills().isEmpty == false)
        #expect(try await client.toolsets().isEmpty == false)
        _ = try await client.kanbanBoard()
        #expect(try await client.kanbanBoards().boards.isEmpty == false)
        _ = try await client.gitStatus(path: "/opt/hermes")

        let created = try await client.createKanbanTask(KanbanTaskDraft(title: "live test"))
        let detail = try await client.kanbanTask(id: created.task.id)
        #expect(detail.task.title == "live test")
        try await client.addKanbanComment(id: created.task.id, text: "hello", author: "tests")
        await #expect(throws: RESTError.self) {
            try await client.updateKanbanTask(id: created.task.id, KanbanTaskUpdate(status: "done"))
        }
        try await client.deleteKanbanTask(id: created.task.id)
    }
}
