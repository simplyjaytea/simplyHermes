import Foundation
import HermesKit
import Testing

private let jsonHeaders = ["Content-Type": "application/json"]

private final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [HTTPResponse] = []
    private var seen: [HTTPRequest] = []

    func enqueue(_ status: Int, _ json: String = "{}", headers: [String: String] = jsonHeaders) {
        lock.withLock { queue.append(HTTPResponse(status: status, headers: headers, body: Data(json.utf8))) }
    }

    var requests: [HTTPRequest] { lock.withLock { seen } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            seen.append(request)
            guard !queue.isEmpty else { throw RESTError.transport("no scripted response") }
            return queue.removeFirst()
        }
    }
}

private func makeClient(
    _ http: FakeHTTP, prefix: String = "", auth: RESTAuth = .cookie, profile: String? = nil,
    clock: ManualClock = ManualClock(),
    reauth: RESTReauthenticator? = nil
) -> RESTClient {
    RESTClient(
        endpoint: HermesEndpoint(string: "https://hermes.example" + prefix)!, transport: http, auth: auth,
        profile: profile,
        clock: clock, reauthenticate: reauth)
}

private struct Pong: Decodable, Sendable, Equatable { var ok: Bool }

@Suite struct RESTClientTests {
    @Test func joinsPrefixAddsProfileAndHeaders() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, prefix: "/hermes", auth: .sessionToken("tok"), profile: "ops team")
        let pong: Pong = try await client.get("/api/health", query: [URLQueryItem(name: "a", value: "b&c")])
        #expect(pong == Pong(ok: true))
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://hermes.example/hermes/api/health?a=b%26c&profile=ops%20team")
        #expect(request.headers["X-Hermes-Session-Token"] == "tok")
        #expect(request.headers["Accept"] == "application/json")
        #expect(request.method == "GET")
    }

    @Test func unscopedCallsSkipTheProfile() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http, profile: "ops")
        let _: Pong = try await client.get("/api/profiles", scoped: false)
        #expect(http.requests.first?.url.query == nil)
    }

    @Test func postSendsJSONBody() async throws {
        struct Body: Encodable, Sendable { var name: String }
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true}"#)
        let client = makeClient(http)
        let _: Pong = try await client.send("POST", "/api/x", body: Body(name: "n"))
        let request = try #require(http.requests.first)
        #expect(request.headers["Content-Type"] == "application/json")
        #expect(String(bytes: request.body ?? Data(), encoding: .utf8) == #"{"name":"n"}"#)
    }

    @Test func rateLimitWaitsRetryAfterThenSucceeds() async throws {
        let http = FakeHTTP()
        http.enqueue(429, headers: ["Retry-After": "7", "Content-Type": "application/json"])
        http.enqueue(200, #"{"ok":true}"#)
        let clock = ManualClock()
        let client = makeClient(http, clock: clock)
        let task = Task {
            let pong: Pong = try await client.get("/api/health")
            return pong
        }
        try await waitUntil("sleeping") { clock.sleeperCount == 1 }
        #expect(http.requests.count == 1)
        await clock.advance(by: 7)
        #expect(try await task.value == Pong(ok: true))
        #expect(http.requests.count == 2)
    }

    @Test func rateLimitGivesUpAfterRetries() async throws {
        let http = FakeHTTP()
        for _ in 0..<4 { http.enqueue(429) }
        let clock = ManualClock()
        let client = makeClient(http, clock: clock)
        let task = Task {
            let pong: Pong = try await client.get("/api/health")
            return pong
        }
        for _ in 0..<3 {
            try await waitUntil("sleeping") { clock.sleeperCount == 1 }
            await clock.advance(by: 60, step: 60)
        }
        await #expect(throws: RESTError.rateLimited(retryAfter: nil)) { _ = try await task.value }
        #expect(http.requests.count == 4)
    }

    @Test func unauthorizedRunsHookOnceAndRetries() async throws {
        let http = FakeHTTP()
        http.enqueue(401)
        http.enqueue(200, #"{"ok":true}"#)
        let calls = Counter()
        let client = makeClient(http, reauth: { calls.bump() })
        let pong: Pong = try await client.get("/api/health")
        #expect(pong == Pong(ok: true))
        #expect(calls.value == 1)
    }

    @Test func secondUnauthorizedFails() async throws {
        let http = FakeHTTP()
        http.enqueue(401)
        http.enqueue(401)
        let client = makeClient(http, reauth: {})
        await #expect(throws: RESTError.unauthorized) { let _: Pong = try await client.get("/api/health") }
    }

    @Test func unauthorizedWithoutHookFails() async throws {
        let http = FakeHTTP()
        http.enqueue(401)
        let client = makeClient(http)
        await #expect(throws: RESTError.unauthorized) { let _: Pong = try await client.get("/api/health") }
    }

    @Test func failingHookMeansUnauthorized() async throws {
        struct Nope: Error {}
        let http = FakeHTTP()
        http.enqueue(401)
        let client = makeClient(http, reauth: { throw Nope() })
        await #expect(throws: RESTError.unauthorized) { let _: Pong = try await client.get("/api/health") }
    }

    @Test func httpErrorCarriesDetail() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"session not found"}"#)
        let client = makeClient(http)
        await #expect(throws: RESTError.http(status: 404, detail: "session not found")) {
            let _: Pong = try await client.get("/api/sessions/x")
        }
    }

    @Test func htmlLoginPageIsNotSuccess() async throws {
        let http = FakeHTTP()
        http.enqueue(200, "<html></html>", headers: ["content-type": "text/html; charset=utf-8"])
        let client = makeClient(http)
        await #expect(throws: RESTError.unexpectedContent(contentType: "text/html; charset=utf-8")) {
            let _: Pong = try await client.get("/openapi.json")
        }
    }

    @Test func badBodyIsADecodingError() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"nope":1}"#)
        let client = makeClient(http)
        do {
            let _: Pong = try await client.get("/api/health")
            Issue.record("expected decoding error")
        } catch let error as RESTError {
            if case .decoding = error { return }
            Issue.record("wrong error \(error)")
        }
    }

    @Test func loginAndTicketHelpers() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"next":""}"#)
        http.enqueue(200, #"{"ticket":"abc","ttl_seconds":30}"#)
        let client = makeClient(http, profile: "ops")
        try await client.passwordLogin(username: "u", password: "p")
        let ticket = try await client.webSocketTicket()
        #expect(ticket == WebSocketTicket(ticket: "abc", ttlSeconds: 30))
        let login = try #require(http.requests.first)
        #expect(login.url.path == "/auth/password-login")
        #expect(login.url.query == nil)
        #expect(String(bytes: login.body ?? Data(), encoding: .utf8)?.contains(#""provider":"basic""#) == true)
    }

    @Test func credentialProviderMintsTicketsAndReauthenticates() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ticket":"t1","ttl_seconds":30}"#)
        http.enqueue(200, #"{"ticket":"t2","ttl_seconds":30}"#)
        let client = makeClient(http)
        let logins = Counter()
        let provider = await client.gatewayCredentialProvider(login: { logins.bump() })
        #expect(try await provider(.initial) == .ticket("t1"))
        #expect(try await provider(.reauthenticate) == .ticket("t2"))
        #expect(logins.value == 1)
    }

    @Test func rejectedLoginMeansSignInRequired() async throws {
        let http = FakeHTTP()
        let client = makeClient(http)
        let provider = await client.gatewayCredentialProvider(login: { throw RESTError.unauthorized })
        await #expect(throws: GatewaySignInRequired.self) { _ = try await provider(.reauthenticate) }
        let noLogin = await client.gatewayCredentialProvider(login: nil)
        await #expect(throws: GatewaySignInRequired.self) { _ = try await noLogin(.reauthenticate) }
    }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func bump() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
