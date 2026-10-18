import Foundation
import HermesKit
import Testing

@Suite struct KanbanPresenceTests {
    @Test func presentWhenTheConfigAnswers() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"board":"default","columns":[]}"#)
        let presence = try await makeClient(http).kanbanPresence()
        #expect(presence == .present)
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/plugins/kanban/config")
        #expect(request.url.query == nil)
    }

    @Test func absentOnNotFound() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"Not Found"}"#)
        let presence = try await makeClient(http).kanbanPresence()
        #expect(presence == .absent)
    }

    @Test func otherFailuresThrowInsteadOfHidingTheFeature() async throws {
        let http = FakeHTTP()
        http.enqueue(500, #"{"detail":"database locked"}"#)
        await #expect(throws: RESTError.http(status: 500, detail: "database locked")) {
            try await makeClient(http).kanbanPresence()
        }
    }

    @Test func aLoginPageIsNotTakenForPresence() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "<html>sign in</html>", headers: ["Content-Type": "text/html"])
        await #expect(throws: RESTError.unexpectedContent(contentType: "text/html")) {
            try await makeClient(http).kanbanPresence()
        }
    }

    @Test func presenceIsCheckedForTheActiveProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"Not Found"}"#)
        _ = try await makeClient(http, profile: "ops").kanbanPresence()
        #expect(http.requests.first?.url.query == "profile=ops")
    }
}
