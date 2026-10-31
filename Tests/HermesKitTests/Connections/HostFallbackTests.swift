import Foundation
import HermesKit
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A resolver with fixed answers.
struct FixedResolver: HostResolving {
    var answers: [String: [String]]
    func addresses(of host: String) async -> [String] { answers[host] ?? [] }
}

/// Records every request and hands each test a named transport, so a test can tell which connection sent what.
final class ProbeRecorder: @unchecked Sendable {
    struct Record {
        let transport: String
        let request: HTTPRequest
    }

    private let lock = NSLock()
    private var records: [Record] = []
    private var answers: [String: (status: Int, body: String)] = [:]
    private var transportCount = 0
    private var imported: [String] = []

    /// Makes a fresh transport, named in the order it was made.
    func makeTransport() -> any HTTPTransport {
        lock.withLock {
            transportCount += 1
            return ProbeTransport(name: "t\(transportCount)", recorder: self)
        }
    }

    /// Answers requests for `host` and `path`.
    func answer(host: String, path: String = "/api/health", status: Int, body: String) {
        lock.withLock { answers["\(host)\(path)"] = (status, body) }
    }

    var requests: [Record] { lock.withLock { records } }

    /// The transports that had cookies imported, by name.
    var importedTransports: [String] { lock.withLock { imported } }

    func record(_ request: HTTPRequest, transport: String) {
        lock.withLock { records.append(Record(transport: transport, request: request)) }
    }

    func noteImport(transport: String) {
        lock.withLock { imported.append(transport) }
    }

    func response(for url: URL) -> HTTPResponse {
        let key = "\(url.host ?? "")\(url.path)"
        let answer = lock.withLock { answers[key] }
        guard let answer else {
            return HTTPResponse(status: 404, headers: jsonHeaders, body: Data("{}".utf8))
        }
        return HTTPResponse(
            status: answer.status, headers: jsonHeaders, body: Data(answer.body.utf8))
    }
}

/// A transport that adds the cookies imported into it, as the real one does.
final class ProbeTransport: HTTPTransport, CookieImporting, @unchecked Sendable {
    let name: String
    let recorder: ProbeRecorder

    private let lock = NSLock()
    private var cookies: [HTTPCookie] = []

    init(name: String, recorder: ProbeRecorder) {
        self.name = name
        self.recorder = recorder
    }

    func importCookies(_ cookies: [HTTPCookie]) {
        lock.withLock { self.cookies.append(contentsOf: cookies) }
        recorder.noteImport(transport: name)
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var sent = request
        let held = lock.withLock { cookies }
        let domainMatched = held.filter {
            $0.domain.isEmpty || $0.domain == request.url.host || request.url.host?.hasSuffix($0.domain) == true
        }
        if let fields = HTTPCookie.requestHeaderFields(with: domainMatched)["Cookie"], sent.headers["Cookie"] == nil {
            sent.headers["Cookie"] = fields
        }
        recorder.record(sent, transport: name)
        return recorder.response(for: request.url)
    }
}

/// The body Hermes sends for a Host it doesn't know. Seen live on a server bound to its Tailscale IP.
let invalidHostBody =
    #"{"detail":"Invalid Host header. Dashboard requests must use the bound hostname or the configured public hostname."}"#

@Suite struct HostFallbackTests {
    private let resolver = FixedResolver(answers: [
        "box": ["100.64.150.77"], "box.tail1234.ts.net": ["100.64.150.77", "fd7a:115c:a1e0::1%utun4"],
    ])

    @Test func swapsTheNameForEachAddressAndKeepsPortAndPath() async throws {
        let endpoint = try #require(HermesEndpoint(string: "http://box.tail1234.ts.net:9119/hermes"))
        let found = await HostFallback.candidates(for: endpoint, resolver: resolver)
        #expect(
            found.map(\.baseURL.absoluteString) == [
                "http://100.64.150.77:9119/hermes", "http://[fd7a:115c:a1e0::1]:9119/hermes",
            ])
    }

    @Test func hasNoFallbackForHTTPSOrAnAddress() async throws {
        let https = try #require(HermesEndpoint(string: "https://box.tail1234.ts.net"))
        #expect(await HostFallback.candidates(for: https, resolver: resolver).isEmpty)
        let address = try #require(HermesEndpoint(string: "http://100.64.150.77:9119"))
        #expect(await HostFallback.candidates(for: address, resolver: resolver).isEmpty)
        let unknown = try #require(HermesEndpoint(string: "http://nowhere:9119"))
        #expect(await HostFallback.candidates(for: unknown, resolver: resolver).isEmpty)
    }

    @Test func noteNamesTheTypedNameAndTheAddress() throws {
        let typed = try #require(HermesEndpoint(string: "http://box:9119"))
        let adapted = try #require(HermesEndpoint(string: "http://100.64.150.77:9119"))
        #expect(
            HostFallback.note(typed: typed, adapted: adapted)
                == "Hermes doesn't answer to box, so the app connects to 100.64.150.77, the same server.")
    }

    @Test func systemResolverFindsLocalhost() async {
        #expect(await SystemHostResolver().addresses(of: "localhost").contains("127.0.0.1"))
    }
}

@Suite struct GatewayHostFallbackTests {
    private let resolver = FixedResolver(answers: ["box": ["100.64.150.77"]])

    private func connection(_ url: String) -> ServerConnection {
        ServerConnection(
            name: "Box",
            kind: .gateway(
                GatewaySettings(endpoint: HermesEndpoint(string: url)!, signIn: .password(username: "hermes"))))
    }

    /// Hermes bound to its Tailscale IP refuses `box` and answers on the IP. The test signs in there and reports the
    /// IP endpoint to save.
    @Test func aRefusedNameSignsInOnTheAddress() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(200, try restFixture("health"))
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, try restFixture("auth_me"))
        http.enqueue(200, #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
        let tester = GatewayConnectionTester(
            makeTransport: { http }, makeAnonymousTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let report = try await tester.test(
            connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
            confirmHostKey: { _ in false })
        #expect(report.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.77:9119")
        #expect(report.signedInAs != nil)
        #expect(
            http.requests.map { "\($0.url.host ?? "") \($0.url.path)" } == [
                "box /api/health", "100.64.150.77 /api/health", "100.64.150.77 /api/status",
                "100.64.150.77 /auth/password-login", "100.64.150.77 /api/auth/me", "100.64.150.77 /api/auth/ws-ticket",
            ])
    }

    @Test func aNameThatWorksIsKept() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("health"))
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, try restFixture("auth_me"))
        http.enqueue(200, #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
        let tester = GatewayConnectionTester(
            makeTransport: { http }, makeAnonymousTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let report = try await tester.test(
            connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
            confirmHostKey: { _ in false })
        #expect(report.adaptedEndpoint == nil)
    }

    @Test func withoutAWorkingAddressTheRefusalStands() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(400, invalidHostBody)
        let tester = GatewayConnectionTester(
            makeTransport: { http }, makeAnonymousTransport: { http }, makeWebSocket: nil, resolver: resolver)
        do {
            _ = try await tester.test(
                connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
                confirmHostKey: { _ in false })
            Issue.record("the test should fail")
        } catch let failure as ConnectionTestFailure {
            #expect(failure.isHostRejected)
        }
    }

    @Test func probeReportsTheAddress() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(200, try restFixture("health"))
        http.enqueue(
            200, #"{"providers":[{"name":"basic","display_name":"Username & Password","supports_password":true}]}"#)
        let tester = GatewayConnectionTester(
            makeTransport: { http }, makeAnonymousTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let probe = try await tester.probe(HermesEndpoint(string: "http://box:9119")!)
        #expect(probe.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.77:9119")
    }
}

@Suite struct GatewayHostFallbackCredentialTests {
    private let resolver = FixedResolver(answers: ["box": ["100.64.150.77", "100.64.150.78"]])

    /// Headers a user could have set on the endpoint. A probe must keep `Host`-style headers and drop credentials.
    private let endpointHeaders = [
        "Host": "box:9119",
        "X-Forwarded-Host": "keep-me",
        "Authorization": "Bearer endpoint-secret",
        "Cookie": "endpoint=cookie-secret",
        "Proxy-Authorization": "Basic endpoint-secret",
        "X-Hermes-Session-Token": "endpoint-secret",
        "X-API-Key": "custom-secret",
        "X-Custom-Token": "other-secret",
        "X-Forwarded-Proto": "https",
    ]

    private func connection(_ signIn: GatewaySignIn) throws -> ServerConnection {
        let endpoint = try #require(HermesEndpoint(string: "http://box:9119", headers: endpointHeaders))
        return ServerConnection(name: "Box", kind: .gateway(GatewaySettings(endpoint: endpoint, signIn: signIn)))
    }

    /// `box` refuses its name, the first address is not Hermes, and the second answers.
    private func route(_ recorder: ProbeRecorder) throws {
        recorder.answer(host: "box", status: 400, body: invalidHostBody)
        recorder.answer(host: "100.64.150.77", status: 404, body: "{}")
        recorder.answer(host: "100.64.150.78", status: 200, body: try restFixture("health"))
        recorder.answer(host: "100.64.150.78", path: "/api/status", status: 200, body: try restFixture("status"))
        recorder.answer(host: "100.64.150.78", path: "/api/auth/me", status: 200, body: try restFixture("auth_me"))
        recorder.answer(
            host: "100.64.150.78", path: "/api/auth/ws-ticket", status: 200,
            body: #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
    }

    /// The anonymous health probes sent to the IP candidates.
    private func probeRequests(_ recorder: ProbeRecorder) -> [ProbeRecorder.Record] {
        recorder.requests.filter { $0.request.url.host != "box" && $0.request.url.path == "/api/health" }
    }

    /// A probe may send routing headers and `Accept`, and nothing else. An unknown header is not assumed safe.
    private func expectOnlyRoutingHeaders(_ request: HTTPRequest, _ context: String) {
        let allowed: Set<String> = ["host", "x-forwarded-host", "accept"]
        for (name, value) in request.headers {
            #expect(allowed.contains(name.lowercased()), "\(context) sent \(name)")
            #expect(!value.contains("secret"), "\(context) sent a secret in \(name)")
        }
        #expect(request.headers["Host"] == "box:9119")
        #expect(request.headers["X-Forwarded-Host"] == "keep-me")
    }

    @Test func everyCandidateIsProbedWithoutTheSessionToken() async throws {
        let recorder = ProbeRecorder()
        try route(recorder)
        let tester = GatewayConnectionTester(
            makeTransport: recorder.makeTransport, makeAnonymousTransport: recorder.makeTransport,
            makeWebSocket: nil, resolver: resolver)
        let report = try await tester.test(
            try connection(.sessionToken), secrets: ConnectionSecrets(sessionToken: "session-secret"),
            progress: { _ in }, confirmHostKey: { _ in false })

        #expect(report.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.78:9119")
        #expect(recorder.importedTransports.isEmpty)

        let candidates = probeRequests(recorder)
        #expect(candidates.map { $0.request.url.host } == ["100.64.150.77", "100.64.150.78"])
        for record in candidates {
            expectOnlyRoutingHeaders(record.request, "candidate \(record.request.url.host ?? "?")")
            #expect(record.request.headers["X-Forwarded-Host"] == "keep-me")
        }
        // The rejected address saw only the anonymous health probe.
        #expect(candidates.first?.request.url.path == "/api/health")

        // Only after the selected address answered as Hermes does it receive the token.
        let selected = recorder.requests.filter {
            $0.request.url.host == "100.64.150.78" && $0.request.url.path == "/api/status"
        }
        #expect(selected.first?.request.headers["X-Hermes-Session-Token"] == "session-secret")
        // Endpoint custom credentials follow only after the address was selected.
        #expect(selected.first?.request.headers["X-API-Key"] == "custom-secret")
    }

    @Test func everyCandidateIsProbedWithoutTheBearerToken() async throws {
        let recorder = ProbeRecorder()
        try route(recorder)
        let tester = GatewayConnectionTester(
            makeTransport: recorder.makeTransport, makeAnonymousTransport: recorder.makeTransport,
            makeWebSocket: nil, resolver: resolver)
        let tokens = NativeTokens(accessToken: "bearer-secret", refreshToken: "refresh", expiresAt: 9_999_999_999)
        let report = try await tester.test(
            try connection(.browser(provider: nil)), secrets: ConnectionSecrets(nativeTokens: tokens),
            progress: { _ in }, confirmHostKey: { _ in false })

        #expect(report.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.78:9119")
        for record in probeRequests(recorder) {
            expectOnlyRoutingHeaders(record.request, "candidate \(record.request.url.host ?? "?")")
        }
        let selected = recorder.requests.first {
            $0.request.url.host == "100.64.150.78" && $0.request.url.path == "/api/status"
        }
        #expect(selected?.request.headers["Authorization"] == "Bearer bearer-secret")
    }

    @Test func candidatesGetNoCookiesFromTheWebSignIn() async throws {
        let recorder = ProbeRecorder()
        try route(recorder)
        let cookie = try #require(
            HTTPCookie(properties: [
                .name: "hermes_session", .value: "cookie-secret", .domain: "box", .path: "/",
            ]))
        let tester = GatewayConnectionTester(
            makeTransport: recorder.makeTransport, makeAnonymousTransport: recorder.makeTransport,
            makeWebSocket: nil, resolver: resolver)
        _ = try await tester.test(
            try connection(.browser(provider: nil)),
            secrets: ConnectionSecrets(webCookies: [StoredCookie(cookie)]), progress: { _ in },
            confirmHostKey: { _ in false })

        // Only the transport for the typed server had cookies imported.
        #expect(recorder.importedTransports == ["t1"])
        for record in probeRequests(recorder) {
            expectOnlyRoutingHeaders(record.request, "candidate \(record.request.url.host ?? "?")")
        }
    }

    @Test func aProbeNeverSendsEndpointCredentials() async throws {
        let recorder = ProbeRecorder()
        try route(recorder)
        recorder.answer(
            host: "100.64.150.78", path: "/api/auth/providers", status: 200,
            body: #"{"providers":[{"name":"basic","display_name":"Password","supports_password":true}]}"#)
        let tester = GatewayConnectionTester(
            makeTransport: recorder.makeTransport, makeAnonymousTransport: recorder.makeTransport,
            makeWebSocket: nil, resolver: resolver)
        let endpoint = try #require(HermesEndpoint(string: "http://box:9119", headers: endpointHeaders))
        let probe = try await tester.probe(endpoint)

        #expect(probe.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.78:9119")
        for record in recorder.requests {
            expectOnlyRoutingHeaders(record.request, "probe \(record.request.url.host ?? "?")")
        }
    }

    @Test func anonymousEndpointDropsCredentialsAndKeepsOtherHeaders() throws {
        let endpoint = try #require(HermesEndpoint(string: "http://box:9119", headers: endpointHeaders))
        let anonymous = GatewayConnectionTester.anonymousEndpoint(endpoint)
        #expect(anonymous.baseURL == endpoint.baseURL)
        #expect(anonymous.headers == ["Host": "box:9119", "X-Forwarded-Host": "keep-me"])
        // Routing names match whatever case the endpoint stored them in; anything else is dropped.
        let mixed = try #require(
            HermesEndpoint(
                string: "http://box:9119",
                headers: ["HOST": "box:9119", "AUTHORIZATION": "x", "X-API-Key": "y", "PROXY-authorization": "z"]))
        #expect(GatewayConnectionTester.anonymousEndpoint(mixed).headers == ["HOST": "box:9119"])
    }
}

/// Runs against a real Hermes when `HERMES_HOST_FALLBACK_URL` names an address it refuses, such as the MagicDNS short
/// name of a server bound to its Tailscale IP.
@Suite struct GatewayHostFallbackLiveTests {
    @Test func probeAdaptsOnARealServer() async throws {
        guard let text = ProcessInfo.processInfo.environment["HERMES_HOST_FALLBACK_URL"],
            let endpoint = HermesEndpoint(string: text)
        else { return }
        let probe = try await GatewayConnectionTester(makeWebSocket: nil).probe(endpoint)
        #expect(probe.adaptedEndpoint != nil)
        #expect(probe.authRequired)
    }
}

private struct FailedProbeTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw RESTError.transport("App Transport Security blocked HTTP (-1022)")
    }
}

@Suite struct GatewayProbeFailureTests {
    @Test func discoveryPreservesTheTransportFailure() async throws {
        let endpoint = try #require(HermesEndpoint(string: "http://100.64.150.77:9119"))
        let tester = GatewayConnectionTester(makeAnonymousTransport: { FailedProbeTransport() })
        do {
            _ = try await tester.probe(endpoint)
            Issue.record("discovery must report the failed request")
        } catch let failure as ConnectionTestFailure {
            #expect(failure == .unreachable("App Transport Security blocked HTTP (-1022)"))
        }
    }

    @Test func discoveryRejectsAnUnhealthyResponse() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":false}"#)
        let tester = GatewayConnectionTester(makeAnonymousTransport: { http })
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        do {
            _ = try await tester.probe(endpoint)
            Issue.record("an unhealthy server must not be discovered")
        } catch let failure as ConnectionTestFailure {
            #expect(failure == .notHermes)
        }
    }
}

@Suite struct GatewayProbeLiveTests {
    @Test func reachesTheConfiguredGatewayWithoutCredentials() async throws {
        guard let text = ProcessInfo.processInfo.environment["HERMES_PROBE_URL"],
            let endpoint = HermesEndpoint(string: text)
        else { return }
        let probe = try await GatewayConnectionTester(makeWebSocket: nil).probe(endpoint)
        #expect(probe.signIn != nil)
    }
}
