import Foundation
import HermesKit
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set. Without it the tests pass without doing anything.
///
/// The testbed's `basic` provider also offers `native_pkce`, so the whole RFC 8252 flow runs here: the "browser" is a
/// second transport that opens the authorize URL and posts the login form, exactly what the login page's script does.
@Suite(.serialized) struct NativeAuthLiveTests {
    private var endpoint: HermesEndpoint? {
        ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"].flatMap { HermesEndpoint(string: $0) }
    }

    @Test func nativePKCESignInRefreshAndChat() async throws {
        guard let endpoint else { return }
        let id = UUID()
        let store = InMemoryCredentialStore()
        let clock = FakeNow(Date().timeIntervalSince1970)
        let session = GatewayAuthSession(
            connectionID: id, settings: GatewaySettings(endpoint: endpoint, signIn: .browser(provider: nil)),
            credentials: store, now: { clock.now })
        try await session.prepare()

        let options = try await SignInOptions.detect(using: session.client)
        #expect(options.supportsNativePKCE)
        #expect(options.methods.contains(.browser))

        // The browser: authorize, then the login form, which answers with the loopback redirect.
        let request = NativeSignInRequest(endpoint: endpoint, port: 53123)
        let browserTransport = URLSessionHTTPTransport()
        let browser = RESTClient(endpoint: endpoint, transport: browserTransport)
        let authorize = try await browserTransport.send(HTTPRequest(method: "GET", url: request.authorizeURL))
        #expect(authorize.status == 302)
        let login: LoginRedirect = try await browser.send(
            "POST", "/auth/password-login",
            body: ["provider": "basic", "username": "tester", "password": "testbed-password", "next": ""],
            scoped: false)
        let redirect = try #require(URL(string: login.next))
        #expect(request.isRedirect(redirect))

        let tokens = try await session.completeBrowserSignIn(request, redirect: redirect)
        #expect(tokens.userID == "tester")
        #expect(try await session.client.currentUser().userId == "tester")
        // The code is single use.
        await #expect(throws: NativeSignInError.codeRejected) {
            try await session.completeBrowserSignIn(request, redirect: redirect)
        }

        // Pretend the access token is about to expire: the next ticket rotates the refresh token first.
        clock.set(tokens.expiresAt - 10)
        let credential = try await session.credentialProvider()(.initial)
        guard case .ticket(let ticket) = credential else { throw LiveFailure("no ticket") }
        #expect(ticket.count > 20)
        let stored = try #require(try store.data(for: .nativeTokens, connection: id))
        #expect(try JSONDecoder().decode(NativeTokens.self, from: stored).expiresAt >= tokens.expiresAt)

        // Chat over the WebSocket with tickets minted by the bearer session.
        let client = GatewayClient(
            endpoint: endpoint, transport: NIOWebSocketTransport(), credentials: session.credentialProvider())
        let events = await client.events()
        await client.start()
        let connected = try await liveTimeout(seconds: 30) { () -> Bool in
            for await event in events where event == .state(.connected) { return true }
            return false
        }
        await client.stop()
        #expect(connected)
    }

    @Test func passwordSignInWithSilentRelogin() async throws {
        guard let endpoint else { return }
        let id = UUID()
        let store = InMemoryCredentialStore()
        let session = GatewayAuthSession(
            connectionID: id, settings: GatewaySettings(endpoint: endpoint, signIn: .password(username: "tester")),
            credentials: store)
        try await session.prepare()
        await #expect(throws: RESTError.unauthorized) { _ = try await session.client.currentUser() }
        try await session.signInWithPassword(username: "tester", password: "testbed-password", remember: true)
        #expect(try await session.client.currentUser().userId == "tester")
        // App restart: a fresh transport has no cookies. The 401 hook signs in again with the stored password.
        let restarted = GatewayAuthSession(
            connectionID: id,
            settings: GatewaySettings(
                endpoint: endpoint, signIn: .password(username: "tester"), remembersPassword: true),
            credentials: store)
        try await restarted.prepare()
        #expect(try await restarted.client.currentUser().userId == "tester")
    }
}

/// Runs when `HERMES_TESTBED_OIDC_URL` is set (`testbed/scripts/up.sh --profile oidc`, dashboard on port 9120):
/// browser sign-in through the `self-hosted` OIDC provider, with Dex as the identity provider.
@Suite struct OIDCSignInLiveTests {
    @Test func nativePKCEThroughDex() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_OIDC_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let id = UUID()
        let session = GatewayAuthSession(
            connectionID: id,
            settings: GatewaySettings(endpoint: endpoint, signIn: .browser(provider: "self-hosted")),
            credentials: InMemoryCredentialStore())
        try await session.prepare()
        let options = try await SignInOptions.detect(using: session.client)
        #expect(options.recommended == .browser)
        #expect(options.browserProviders.map(\.name) == ["self-hosted"])

        let request = NativeSignInRequest(endpoint: endpoint, provider: "self-hosted", port: 53124)
        let browser = ScriptedBrowser()
        // Gateway -> Dex -> Dex login form.
        var page = try await browser.follow(request.authorizeURL, until: request)
        let form = try #require(page.formAction, "no Dex login form")
        let action = try #require(URL(string: form, relativeTo: page.url)?.absoluteURL)
        // Dex -> gateway callback -> loopback redirect.
        page = try await browser.post(
            action, form: ["login": "tester@example.com", "password": "password"], until: request)
        let redirect = try #require(page.redirect, "no loopback redirect")

        try await session.completeBrowserSignIn(request, redirect: redirect)
        let user = try await session.client.currentUser()
        #expect(user.provider == "self-hosted")
        guard case .ticket = try await session.credentialProvider()(.initial) else { throw LiveFailure("no ticket") }
    }
}

/// Follows redirects the way a browser would, with one cookie jar, and stops at the loopback redirect.
private final class ScriptedBrowser: @unchecked Sendable {
    struct Page {
        var url: URL
        var body: String
        var redirect: URL?

        /// The first `<form action="…">`, HTML entities for `&` decoded.
        var formAction: String? {
            guard let range = body.range(of: #"action="[^"]*""#, options: .regularExpression) else { return nil }
            return String(body[range]).dropFirst(8).dropLast().replacingOccurrences(of: "&amp;", with: "&")
        }
    }

    private let transport = URLSessionHTTPTransport()

    func follow(_ url: URL, until request: NativeSignInRequest) async throws -> Page {
        try await run(HTTPRequest(method: "GET", url: url), until: request)
    }

    func post(_ url: URL, form: [String: String], until request: NativeSignInRequest) async throws -> Page {
        var components = URLComponents()
        components.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        let body = Data((components.percentEncodedQuery ?? "").utf8)
        let post = HTTPRequest(
            method: "POST", url: url, headers: ["Content-Type": "application/x-www-form-urlencoded"], body: body)
        return try await run(post, until: request)
    }

    private func run(_ first: HTTPRequest, until request: NativeSignInRequest) async throws -> Page {
        var next = first
        for _ in 0..<10 {
            let response = try await transport.send(next)
            guard (300..<400).contains(response.status), let location = response.headers["location"],
                let target = URL(string: location, relativeTo: next.url)?.absoluteURL
            else {
                return Page(url: next.url, body: String(bytes: response.body, encoding: .utf8) ?? "")
            }
            if request.isRedirect(target) { return Page(url: next.url, body: "", redirect: target) }
            next = HTTPRequest(method: "GET", url: target)
        }
        throw LiveFailure("too many redirects")
    }
}

private struct LoginRedirect: Decodable, Sendable {
    var ok: Bool
    var next: String
}

struct LiveFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func liveTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
