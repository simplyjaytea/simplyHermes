import Foundation
import HermesKit
import Testing

/// WP-13 CI gate: PKCE, the native redirect, refresh rotation and silent re-login.
@Suite struct PKCETests {
    @Test func challengeMatchesRFC7636AppendixB() {
        let pair = PKCEPair(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk", state: "s")
        #expect(pair.challenge == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func generatedPairsAreURLSafeAndUnique() {
        let first = PKCEPair.generate()
        let second = PKCEPair.generate()
        #expect(first.verifier.count == 43)
        #expect(first.verifier != second.verifier && first.state != second.state)
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(first.verifier.unicodeScalars.allSatisfy(allowed.contains))
        #expect(first.challenge == PKCEPair.challenge(for: first.verifier))
    }
}

@Suite struct NativeSignInRequestTests {
    private let pkce = PKCEPair(verifier: "verifier-0123456789-verifier-0123456789-abc", state: "st+ate/1")

    @Test func authorizeURLKeepsThePrefixAndEncodesEverything() throws {
        let endpoint = try #require(HermesEndpoint(string: "https://box.example/hermes"))
        let request = NativeSignInRequest(endpoint: endpoint, provider: "nous", port: 51234, pkce: pkce)
        let url = request.authorizeURL.absoluteString
        #expect(url.hasPrefix("https://box.example/hermes/auth/native/authorize?provider=nous&"))
        #expect(url.contains("code_challenge=\(pkce.challenge)"))
        #expect(url.contains("code_challenge_method=S256"))
        #expect(url.contains("redirect_uri=http://127.0.0.1:51234/cb"))
        #expect(url.contains("state=st%2Bate/1"))
        let items = URLComponents(url: request.authorizeURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(items.first { $0.name == "state" }?.value == "st+ate/1")
    }

    @Test func noProviderLetsTheServerChoose() throws {
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        let request = NativeSignInRequest(endpoint: endpoint, port: 1, pkce: pkce)
        #expect(!request.authorizeURL.absoluteString.contains("provider="))
    }

    @Test func redirectChecksState() throws {
        let endpoint = try #require(HermesEndpoint(string: "http://127.0.0.1:9119"))
        let request = NativeSignInRequest(endpoint: endpoint, port: 5000, pkce: pkce)
        let good = try #require(URL(string: "http://127.0.0.1:5000/cb?code=abc&state=st%2Bate/1"))
        #expect(request.isRedirect(good))
        #expect(try request.code(from: good) == "abc")
        let forged = try #require(URL(string: "http://127.0.0.1:5000/cb?code=abc&state=other"))
        #expect(throws: NativeSignInError.stateMismatch) { try request.code(from: forged) }
        let denied = try #require(URL(string: "http://127.0.0.1:5000/cb?error=access_denied&state=x"))
        #expect(throws: NativeSignInError.server("access_denied")) { try request.code(from: denied) }
        let empty = try #require(URL(string: "http://127.0.0.1:5000/cb?state=st%2Bate/1"))
        #expect(throws: NativeSignInError.missingCode) { try request.code(from: empty) }
        #expect(!request.isRedirect(try #require(URL(string: "http://127.0.0.1:5001/cb?code=a"))))
    }
}

@Suite struct SignInOptionsTests {
    @Test func methodsFollowProvidersAndFlows() {
        let basic = AuthProviderInfo(name: "basic", supportsPassword: true)
        let nous = AuthProviderInfo(name: "nous", displayName: "Nous Portal", supportsPassword: false)
        let basicOnly = SignInOptions(authRequired: true, providers: [basic], flows: ["cookie", "native_pkce"])
        #expect(basicOnly.methods == [.browser, .password, .sessionToken])
        #expect(basicOnly.recommended == .password)
        let oauth = SignInOptions(authRequired: true, providers: [nous], flows: ["cookie"])
        #expect(oauth.methods == [.browser, .sessionToken])
        #expect(oauth.recommended == .browser)
        #expect(!oauth.supportsNativePKCE)
        let open = SignInOptions(authRequired: false, providers: [], flows: [])
        #expect(open.methods.isEmpty && open.recommended == nil)
    }

    @Test func detectReadsStatusAndProviders() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"providers":[{"name":"basic","display_name":"Password","supports_password":true}]}"#)
        let client = RESTClient(endpoint: try #require(HermesEndpoint(string: "http://h:1")), transport: http)
        let options = try await SignInOptions.detect(using: client)
        #expect(options.authRequired && options.supportsNativePKCE)
        #expect(options.passwordProvider?.displayName == "Password")
    }
}

/// A transport that answers by path, so concurrent requests need no fixed order.
final class RoutedHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var routes: [String: [HTTPResponse]] = [:]
    private var seen: [HTTPRequest] = []

    func on(_ path: String, _ status: Int, _ json: String = "{}") {
        lock.withLock {
            routes[path, default: []].append(HTTPResponse(status: status, headers: jsonHeaders, body: Data(json.utf8)))
        }
    }

    /// Drops queued answers for `path`.
    func clear(_ path: String) { lock.withLock { routes[path] = nil } }

    var requests: [HTTPRequest] { lock.withLock { seen } }

    func requests(to path: String) -> [HTTPRequest] { requests.filter { $0.url.path == path } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            seen.append(request)
            guard var queue = routes[request.url.path], !queue.isEmpty else {
                throw RESTError.transport("no route for \(request.url.path)")
            }
            let response = queue.removeFirst()
            routes[request.url.path] = queue.isEmpty ? [response] : queue
            return response
        }
    }
}

final class FakeNow: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Double
    init(_ value: Double) { self.value = value }
    var now: Double { lock.withLock { value } }
    func set(_ new: Double) { lock.withLock { value = new } }
}

@Suite struct GatewayAuthSessionTests {
    let id = UUID()
    let endpoint = HermesEndpoint(string: "http://127.0.0.1:9119")!

    func tokensJSON(_ access: String, _ refresh: String, expires: Double) -> String {
        #"{"access_token":"\#(access)","refresh_token":"\#(refresh)","token_type":"Bearer","#
            + #""expires_at":\#(expires),"provider":"basic","user_id":"tester"}"#
    }

    func makeSession(
        _ http: RoutedHTTP, signIn: GatewaySignIn, remember: Bool = false, store: InMemoryCredentialStore,
        clock: FakeNow
    ) -> GatewayAuthSession {
        GatewayAuthSession(
            connectionID: id,
            settings: GatewaySettings(endpoint: endpoint, signIn: signIn, remembersPassword: remember),
            credentials: store, transport: http, clock: ManualClock(), now: { clock.now })
    }

    @Test func browserSignInRedeemsTheCodeAndUsesTheBearer() async throws {
        let http = RoutedHTTP()
        http.on("/auth/native/token", 200, tokensJSON("A1", "R1", expires: 10_000))
        http.on("/api/auth/me", 200, #"{"user_id":"tester"}"#)
        let store = InMemoryCredentialStore()
        let session = makeSession(http, signIn: .browser(provider: nil), store: store, clock: FakeNow(1_000))
        try await session.prepare()
        let request = NativeSignInRequest(endpoint: endpoint, port: 4000)
        let redirect = try #require(URL(string: "http://127.0.0.1:4000/cb?code=C1&state=\(request.pkce.state)"))
        try await session.completeBrowserSignIn(request, redirect: redirect)
        _ = try await session.client.currentUser()
        let body = try #require(http.requests(to: "/auth/native/token").first?.body)
        let sent = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(sent == ["code": "C1", "code_verifier": request.pkce.verifier])
        #expect(http.requests(to: "/api/auth/me").last?.headers["Authorization"] == "Bearer A1")
        let stored = try #require(try store.data(for: .nativeTokens, connection: id))
        #expect(try JSONDecoder().decode(NativeTokens.self, from: stored).refreshToken == "R1")
    }

    @Test func unauthorizedRotatesTheRefreshTokenOnceForConcurrentCalls() async throws {
        let http = RoutedHTTP()
        let store = InMemoryCredentialStore()
        let old = NativeTokens(accessToken: "A1", refreshToken: "R1", expiresAt: 10_000, provider: "basic")
        try store.set(try JSONEncoder().encode(old), for: .nativeTokens, connection: id)
        http.on("/api/auth/me", 401)
        http.on("/api/auth/me", 401)
        http.on("/api/auth/me", 200, #"{"user_id":"tester"}"#)
        http.on("/auth/native/refresh", 200, tokensJSON("A2", "R2", expires: 20_000))
        let session = makeSession(http, signIn: .browser(provider: "basic"), store: store, clock: FakeNow(1_000))
        try await session.prepare()
        async let first = session.client.currentUser()
        async let second = session.client.currentUser()
        _ = try await (first, second)
        #expect(http.requests(to: "/auth/native/refresh").count == 1)
        let refreshBody = try #require(http.requests(to: "/auth/native/refresh").first?.body)
        #expect((String(bytes: refreshBody, encoding: .utf8) ?? "").contains(#""refresh_token":"R1""#))
        #expect(http.requests(to: "/api/auth/me").last?.headers["Authorization"] == "Bearer A2")
        let stored = try #require(try store.data(for: .nativeTokens, connection: id))
        #expect(try JSONDecoder().decode(NativeTokens.self, from: stored).refreshToken == "R2")
    }

    @Test func expiringTokenIsRefreshedBeforeMintingATicket() async throws {
        let http = RoutedHTTP()
        let store = InMemoryCredentialStore()
        let clock = FakeNow(1_000)
        let old = NativeTokens(accessToken: "A1", refreshToken: "R1", expiresAt: 5_000)
        try store.set(try JSONEncoder().encode(old), for: .nativeTokens, connection: id)
        http.on("/auth/native/refresh", 200, tokensJSON("A2", "R2", expires: 9_000))
        http.on("/api/auth/ws-ticket", 200, #"{"ticket":"T","ttl_seconds":30}"#)
        let session = makeSession(http, signIn: .browser(provider: nil), store: store, clock: clock)
        try await session.prepare()
        #expect(http.requests(to: "/auth/native/refresh").isEmpty)
        clock.set(4_970)
        let credential = try await session.credentialProvider()(.initial)
        #expect(credential == .ticket("T"))
        #expect(http.requests(to: "/auth/native/refresh").count == 1)
        #expect(http.requests(to: "/api/auth/ws-ticket").last?.headers["Authorization"] == "Bearer A2")
    }

    @Test func refusedRefreshTokenSignsOut() async throws {
        let http = RoutedHTTP()
        let store = InMemoryCredentialStore()
        let old = NativeTokens(accessToken: "A1", refreshToken: "R1", expiresAt: 10_000)
        try store.set(try JSONEncoder().encode(old), for: .nativeTokens, connection: id)
        http.on("/api/auth/me", 401)
        http.on("/auth/native/refresh", 401, #"{"error":"session_expired"}"#)
        let session = makeSession(http, signIn: .browser(provider: nil), store: store, clock: FakeNow(1_000))
        try await session.prepare()
        await #expect(throws: RESTError.unauthorized) { _ = try await session.client.currentUser() }
        #expect(try store.data(for: .nativeTokens, connection: id) == nil)
        #expect(await session.hasBrowserTokens == false)
        await #expect(throws: GatewaySignInRequired.self) {
            _ = try await session.credentialProvider()(.reauthenticate)
        }
    }

    @Test func silentPasswordReloginIsOptInAndThrottled() async throws {
        let http = RoutedHTTP()
        let store = InMemoryCredentialStore()
        let clock = FakeNow(1_000)
        try store.setString("pw", for: .gatewayPassword, connection: id)
        http.on("/api/auth/me", 401)
        http.on("/api/auth/me", 200, #"{"user_id":"tester"}"#)
        http.on("/auth/password-login", 200, #"{"ok":true}"#)
        let session = makeSession(
            http, signIn: .password(username: "tester"), remember: true, store: store, clock: clock)
        try await session.prepare()
        _ = try await session.client.currentUser()
        #expect(http.requests(to: "/auth/password-login").count == 1)
        // Inside the interval a second 401 does not try again: the user must sign in.
        http.clear("/api/auth/me")
        http.on("/api/auth/me", 401)
        clock.set(1_030)
        await #expect(throws: RESTError.unauthorized) { _ = try await session.client.currentUser() }
        #expect(http.requests(to: "/auth/password-login").count == 1)

        let forgetful = makeSession(http, signIn: .password(username: "tester"), store: store, clock: clock)
        try await forgetful.prepare()
        await #expect(throws: RESTError.unauthorized) { _ = try await forgetful.client.currentUser() }
        #expect(http.requests(to: "/auth/password-login").count == 1)
    }

    @Test func passwordSignInStoresThePasswordOnlyWhenAsked() async throws {
        let http = RoutedHTTP()
        http.on("/auth/password-login", 200, #"{"ok":true}"#)
        let store = InMemoryCredentialStore()
        let session = makeSession(http, signIn: .none, store: store, clock: FakeNow(0))
        try await session.signInWithPassword(username: "tester", password: "pw", remember: true)
        #expect(try store.string(for: .gatewayPassword, connection: id) == "pw")
        try await session.signInWithPassword(username: "tester", password: "pw", remember: false)
        #expect(try store.string(for: .gatewayPassword, connection: id) == nil)
    }
}
