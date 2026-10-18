import Foundation
import HermesKit
import Testing

/// Checks the method, path, query and body each server-control call sends.
@Suite struct ServerControlRequestTests {
    private func bodyObject(_ request: HTTPRequest) -> [String: Any]? {
        request.body.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    @Test func logsSendTheFilterAndTheProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"lines": []}"#)
        let filter = ServerLogsFilter(file: "agent", level: .warning, search: "retry", lines: 100)
        _ = try await makeClient(http, profile: "ops").serverLogs(filter)
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/logs")
        #expect(request.url.query == "file=agent&lines=100&level=WARNING&search=retry&profile=ops")
    }

    @Test func analyticsSendTheWindow() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        http.enqueue(200, "{}")
        let client = makeClient(http)
        _ = try await client.analyticsUsage(days: 7)
        _ = try await client.analyticsModels(days: 90)
        let requests = http.requests
        #expect(requests.map(\.url.path) == ["/api/analytics/usage", "/api/analytics/models"])
        #expect(requests.map { $0.url.query } == ["days=7", "days=90"])
    }

    @Test func statsHealthAndStatusAreNotProfileScoped() async throws {
        let http = FakeHTTP()
        for _ in 0..<3 { http.enqueue(200, "{}") }
        let client = makeClient(http, profile: "ops")
        _ = try await client.systemStats()
        _ = try await client.healthIdle()
        _ = try await client.controlStatus()
        let requests = http.requests
        #expect(requests.map(\.url.path) == ["/api/system/stats", "/api/health/idle", "/api/status"])
        #expect(requests.allSatisfy { $0.url.query == nil && $0.method == "GET" })
    }

    @Test func startStopRestartArePostsToTheirOwnPaths() async throws {
        let http = FakeHTTP()
        for _ in 0..<3 { http.enqueue(200, #"{"ok": true}"#) }
        let client = makeClient(http, profile: "ops")
        try await client.gatewayControl(.start)
        try await client.gatewayControl(.stop)
        try await client.gatewayControl(.restart)
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "POST", "POST"])
        #expect(requests.map(\.url.path) == ["/api/gateway/start", "/api/gateway/stop", "/api/gateway/restart"])
        #expect(requests.allSatisfy { $0.url.query == "profile=ops" && $0.body == nil })
    }

    @Test func drainAndCancelDrainSendTheActionInTheBody() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok": true}"#)
        http.enqueue(200, #"{"ok": true}"#)
        let client = makeClient(http, profile: "ops")
        try await client.gatewayControl(.drain)
        try await client.gatewayControl(.cancelDrain)
        let requests = http.requests
        #expect(requests.map(\.url.path) == ["/api/gateway/drain", "/api/gateway/drain"])
        #expect(requests.allSatisfy { $0.method == "POST" && $0.url.query == nil })
        #expect(bodyObject(requests[0])?["action"] as? String == "drain")
        #expect(bodyObject(requests[1])?["action"] as? String == "cancel")
        #expect(bodyObject(requests[0])?.count == 1)
    }

    @Test func updateCheckSendsTheForceFlag() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        http.enqueue(200, "{}")
        let client = makeClient(http, profile: "ops")
        _ = try await client.hermesUpdateCheck(force: false)
        _ = try await client.hermesUpdateCheck(force: true)
        #expect(http.requests.map(\.url.query) == ["force=false&profile=ops", "force=true&profile=ops"])
        #expect(http.requests.allSatisfy { $0.url.path == "/api/hermes/update/check" && $0.method == "GET" })
    }

    @Test func updateStartIsAnUnscopedPost() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok": true}"#)
        try await makeClient(http, profile: "ops").hermesUpdate()
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/hermes/update")
        #expect(request.url.query == nil && request.body == nil)
    }

    @Test func receiptIsAnUnscopedGet() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "{}")
        _ = try await makeClient(http, profile: "ops").hermesUpdateReceipt()
        let request = try #require(http.requests.first)
        #expect(request.method == "GET" && request.url.path == "/api/hermes/update/receipt")
        #expect(request.url.query == nil)
    }

    @Test func actionsKnowWhichOnesWaitForTheServer() {
        #expect(ServerControlAction.allCases.filter(\.waitsForServer) == [.stop, .restart])
        #expect(ServerLogsLevel.error.apiValue == "ERROR" && ServerLogsLevel.all.apiValue == nil)
    }
}
