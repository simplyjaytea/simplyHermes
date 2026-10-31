import Foundation

/// Secrets for a connection test, taken from the form before anything is saved.
public struct ConnectionSecrets: Sendable, Equatable {
    /// Gateway `basic` password.
    public var password: String?
    /// Gateway session token.
    public var sessionToken: String?
    /// SSH private key.
    public var sshKey: StoredSSHKey?
    /// SSH password.
    public var sshPassword: String?
    /// Tokens from browser sign-in.
    public var nativeTokens: NativeTokens?
    /// Session cookies from the web view sign-in, on servers without native sign-in.
    public var webCookies: [StoredCookie]?

    /// Creates a value.
    public init(
        password: String? = nil, sessionToken: String? = nil, sshKey: StoredSSHKey? = nil, sshPassword: String? = nil,
        nativeTokens: NativeTokens? = nil, webCookies: [StoredCookie]? = nil
    ) {
        self.password = password
        self.sessionToken = sessionToken
        self.sshKey = sshKey
        self.sshPassword = sshPassword
        self.nativeTokens = nativeTokens
        self.webCookies = webCookies
    }
}

/// What a connection test is doing now, for the progress row.
public enum ConnectionTestStep: Sendable, Equatable {
    case reachingServer
    case signingIn
    case checkingServer
    case connectingSSH
    case startingDashboard
    case forwarding
    case openingWebSocket

    /// Short text for the progress row.
    public var title: String {
        switch self {
        case .reachingServer: "Reaching the server…"
        case .signingIn: "Signing in…"
        case .checkingServer: "Checking Hermes…"
        case .connectingSSH: "Connecting over SSH…"
        case .startingDashboard: "Starting Hermes on the server…"
        case .forwarding: "Opening the tunnel…"
        case .openingWebSocket: "Opening the live connection…"
        }
    }
}

/// A passed connection test.
public struct ConnectionTestReport: Sendable, Equatable {
    /// Version for display, such as `git.d97007c`.
    public var serverVersion: String?
    /// Release date, used for compatibility checks.
    public var releaseDate: String?
    /// The signed-in user, when the server needs a login.
    public var signedInAs: String?
    /// Login providers the server offers, such as `basic`.
    public var authProviders: [String]
    /// SSH: the host key the user trusted. Save it to pin later connects.
    public var acceptedHostKey: HostKeyFingerprint?
    /// True when the WebSocket leg ran and passed (WP-15). False when the tester had no WebSocket transport.
    public var webSocketChecked = false
    /// The compatibility verdict from `/api/status`.
    public var compatibility: ServerCompatibility = .compatible
    /// Set when Hermes refused the typed name and answered on one of its IP addresses instead (``HostFallback``).
    /// Save this endpoint, not the typed one.
    ///
    /// A Hermes health answer on an address is not proof that the address is the same machine: over plain HTTP
    /// nothing authenticates the server, and any host that speaks Hermes can answer. The fallback is a convenience
    /// for a server that refuses its name, not a cryptographic identity check.
    public var adaptedEndpoint: HermesEndpoint?

    /// Creates a report.
    public init(
        serverVersion: String? = nil, releaseDate: String? = nil, signedInAs: String? = nil,
        authProviders: [String] = [], acceptedHostKey: HostKeyFingerprint? = nil
    ) {
        self.serverVersion = serverVersion
        self.releaseDate = releaseDate
        self.signedInAs = signedInAs
        self.authProviders = authProviders
        self.acceptedHostKey = acceptedHostKey
    }

    /// True when the server uses password sign-in, so the app shows the `HERMES_DASHBOARD_BASIC_AUTH_SECRET` tip
    /// (without it, every server restart signs everyone out).
    public var usesBasicAuth: Bool { authProviders.contains("basic") }
}

/// Why a connection test failed, in words the user can act on.
public enum ConnectionTestFailure: Error, Sendable, Equatable {
    /// No answer. `detail` is the system's reason.
    case unreachable(String)
    /// Something answered, but not a Hermes dashboard.
    case notHermes
    /// The server needs a login and none is set. `providers` are what it offers.
    case signInRequired(providers: [String])
    /// Wrong user name, password or token.
    case wrongCredentials
    /// Too many sign-in attempts.
    case rateLimited(retryAfter: Double?)
    /// An unexpected HTTP status.
    case server(status: Int, detail: String?)
    /// The form has no password, token or key.
    case missingSecret
    /// The user did not trust the SSH host key.
    case hostKeyRejected
    /// The SSH host key differs from the pinned one.
    case hostKeyChanged(expected: String, actual: String)
    /// SSH failed: login refused, `hermes` not found, too old, or another reason.
    case ssh(String)
    /// A form field is missing or wrong.
    case invalidForm(String)
    /// HTTP worked but the WebSocket did not.
    case webSocket(String)
    /// The server's Hermes is older than this app supports. `found` says what was too old.
    case serverTooOld(found: String)

    /// One or two sentences for the form.
    public var message: String {
        switch self {
        case .unreachable(let detail):
            "Couldn't reach the server. Check the address and that Hermes is running. (\(detail))"
        case .notHermes:
            "Something answered, but it isn't a Hermes dashboard. Check the address and path."
        case .signInRequired(let providers):
            providers.contains("basic")
                ? "This server needs a sign-in. Choose Password and enter the dashboard login."
                : "This server needs a sign-in. Choose Browser and sign in."
        case .wrongCredentials:
            "The server refused the sign-in. Check the user name and password or token."
        case .rateLimited(let retryAfter):
            retryAfter.map { "Too many sign-in attempts. Try again in \(Int($0)) seconds." }
                ?? "Too many sign-in attempts. Try again in a minute."
        case .server(let status, let detail):
            isHostRejected
                ? "Hermes refused this address. It answers only to the address it listens on and to its public URL. "
                    + "Use the address it listens on, such as its Tailscale IP and port, or set "
                    + "HERMES_DASHBOARD_PUBLIC_URL on the server to this address."
                : "The server answered \(status)\(detail.map { ": \($0)" } ?? ".")"
        case .missingSecret:
            "Enter the password, token or key first."
        case .hostKeyRejected:
            "You didn't trust the server's key, so the app disconnected."
        case .hostKeyChanged:
            "The server's key changed since you trusted it. This can mean someone is intercepting the connection."
        case .ssh(let detail), .invalidForm(let detail):
            detail
        case .webSocket(let detail):
            "The server answered, but the live connection (WebSocket) failed. A proxy in front of Hermes may block "
                + "WebSockets. (\(detail))"
        case .serverTooOld(let found):
            "This Hermes is too old for simplyHermes (\(found)). Update Hermes on the server with `hermes update`."
        }
    }

    /// True when Hermes refused the request's `Host`: the address is a name Hermes doesn't know, such as the
    /// `tailscale serve` name in front of a server bound to its Tailscale IP, or a MagicDNS short name.
    public var isHostRejected: Bool {
        guard case .server(400, let detail?) = self else { return false }
        return detail.contains("Invalid Host header")
    }
}

/// What the gateway says about sign-in before the user signs in.
public struct ServerProbe: Sendable, Equatable {
    /// True when the server needs a login.
    public var authRequired: Bool
    /// Login providers such as `basic`.
    public var authProviders: [String]
    /// The full sign-in options (providers and flows), when the server sent them.
    public var signIn: SignInOptions?
    /// Set when Hermes refused the typed name and answered on this IP address instead (``HostFallback``).
    public var adaptedEndpoint: HermesEndpoint?

    /// Creates a value.
    public init(authRequired: Bool, authProviders: [String], signIn: SignInOptions? = nil) {
        self.authRequired = authRequired
        self.authProviders = authProviders
        self.signIn = signIn
    }
}

/// Runs a connection test: reach the server, sign in, check Hermes.
public protocol ConnectionTesting: Sendable {
    /// Tests `connection` with `secrets`. Reports steps through `progress`. SSH asks `confirmHostKey` on first
    /// connect. Throws ``ConnectionTestFailure``.
    func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport
}

/// Tests a gateway connection: the HTTP leg (health, status, compatibility, sign-in), then the WebSocket leg
/// (open `/api/ws` with a fresh ticket, wait for the handshake, call `gateway.capabilities`).
public struct GatewayConnectionTester: ConnectionTesting {
    private let makeTransport: @Sendable () -> any HTTPTransport
    private let makeAnonymousTransport: @Sendable () -> any HTTPTransport
    private let makeWebSocket: (@Sendable () -> any WebSocketTransport)?
    private let webSocketTimeout: Double
    private let resolver: any HostResolving

    /// Creates a tester. `makeTransport` gives each test a fresh transport (its own cookies). `makeAnonymousTransport`
    /// gives health probes a transport that sends and stores no cookies; the default disables both, and it is separate
    /// so a probe can never inherit the test's credentials. Without `makeWebSocket` (Linux, where Foundation has no
    /// WebSockets) the WebSocket leg is skipped.
    public init(
        makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionHTTPTransport(timeout: 15) },
        makeAnonymousTransport: (@Sendable () -> any HTTPTransport)? = nil,
        makeWebSocket: (@Sendable () -> any WebSocketTransport)? = Self.defaultWebSocket, webSocketTimeout: Double = 15,
        resolver: any HostResolving = SystemHostResolver()
    ) {
        self.makeTransport = makeTransport
        self.makeAnonymousTransport =
            makeAnonymousTransport ?? { URLSessionHTTPTransport.anonymous(timeout: 15) }
        self.makeWebSocket = makeWebSocket
        self.webSocketTimeout = webSocketTimeout
        self.resolver = resolver
    }

    /// `URLSessionWebSocketTransport` on Apple platforms, nil elsewhere.
    public static var defaultWebSocket: (@Sendable () -> any WebSocketTransport)? {
        #if canImport(Darwin)
            { URLSessionWebSocketTransport() }
        #else
            nil
        #endif
    }

    /// How the REST client authenticates for `signIn`. Throws ``ConnectionTestFailure/missingSecret``.
    static func auth(for signIn: GatewaySignIn, secrets: ConnectionSecrets) throws -> RESTAuth {
        switch signIn {
        case .sessionToken:
            guard let token = secrets.sessionToken, !token.isEmpty else { throw ConnectionTestFailure.missingSecret }
            return .sessionToken(token)
        case .browser:
            if let tokens = secrets.nativeTokens { return .bearer(tokens.accessToken) }
            guard secrets.webCookies?.isEmpty == false else { throw ConnectionTestFailure.missingSecret }
            return .cookie
        case .none, .password:
            return .cookie
        }
    }

    public func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        guard case .gateway(let settings) = connection.kind else {
            throw ConnectionTestFailure.server(status: 0, detail: "not a gateway connection")
        }
        let auth = try Self.auth(for: settings.signIn, secrets: secrets)
        var config = RESTClientConfig()
        config.maxRateLimitRetries = 0
        let transport = makeTransport()
        if let cookies = secrets.webCookies, let importer = transport as? any CookieImporting {
            importer.importCookies(cookies.compactMap(\.cookie))
        }
        var endpoint = settings.endpoint
        var client = RESTClient(endpoint: endpoint, transport: transport, auth: auth, config: config)

        progress(.reachingServer)
        let health: ServerHealth
        do {
            health = try await client.health()
        } catch {
            let failure = Self.reachFailure(error)
            guard failure.isHostRejected,
                let found = await reachByAddress(endpoint, config: config)
            else { throw failure }
            endpoint = found.endpoint
            health = found.health
            // The address answered as Hermes without credentials. Only now, for that selected address, make the
            // authenticated client the rest of the test uses.
            client = RESTClient(endpoint: endpoint, transport: transport, auth: auth, config: config)
        }
        guard health.ok else { throw ConnectionTestFailure.notHermes }
        let status = try? await client.status()
        var report = ConnectionTestReport(
            serverVersion: health.displayVersion ?? health.version, releaseDate: status?.releaseDate,
            authProviders: status?.authProviders ?? [])
        if endpoint != settings.endpoint { report.adaptedEndpoint = endpoint }
        report.compatibility = try Self.compatibility(status)
        let authRequired = health.authRequired ?? status?.authRequired ?? false

        if authRequired {
            progress(.signingIn)
            report.signedInAs = try await signIn(
                client, settings.signIn, secrets: secrets, providers: report.authProviders)
        }
        progress(.checkingServer)
        if authRequired {
            // The ticket proves the session may open the WebSocket; the leg below mints its own.
            do {
                _ = try await client.webSocketTicket()
            } catch {
                throw Self.signInFailure(error)
            }
        }
        if let makeWebSocket {
            progress(.openingWebSocket)
            let client = client
            try await webSocketLeg(
                endpoint, transport: makeWebSocket(),
                credential: { _ in
                    authRequired ? .ticket(try await client.webSocketTicket().ticket) : .none
                })
            report.webSocketChecked = true
        }
        return report
    }

    private static func compatibility(_ status: ServerStatus?) throws -> ServerCompatibility {
        guard let status else { return .compatible }
        let result = ServerCompatibility.check(status)
        if case .updateRequired(let found) = result {
            throw ConnectionTestFailure.serverTooOld(found: found)
        }
        return result
    }

    /// Headers a health probe may send. They route the request to the right virtual host; none identifies the user.
    static let probeHeaderNames: Set<String> = ["host", "x-forwarded-host"]

    /// `endpoint` with only its safe routing headers, for a health probe that must stay anonymous.
    ///
    /// A probe sends an allowlist, not everything except a few known secrets: an endpoint can carry a custom
    /// credential such as `X-API-Key`, and an unknown name must not reach an address that has not answered as Hermes.
    /// `Host` and `X-Forwarded-Host` are kept because a forwarder may need them to route.
    public static func anonymousEndpoint(_ endpoint: HermesEndpoint) -> HermesEndpoint {
        let kept = endpoint.headers.filter { probeHeaderNames.contains($0.key.lowercased()) }
        guard kept.count != endpoint.headers.count else { return endpoint }
        return HermesEndpoint(baseURL: endpoint.baseURL, headers: kept) ?? endpoint
    }

    /// The first IP address of `endpoint`'s name that answers as Hermes, and its health. Nil when none does or there
    /// is no fallback (``HostFallback``).
    ///
    /// Every candidate is probed anonymously: an anonymous transport that sends and stores no cookies, no REST auth,
    /// and only the routing headers from the endpoint. A rejected address never sees the user's secrets. A health
    /// answer only shows that something speaking Hermes is there; over plain HTTP it does not prove which machine it
    /// is.
    private func reachByAddress(
        _ endpoint: HermesEndpoint, config: RESTClientConfig
    ) async -> (endpoint: HermesEndpoint, health: ServerHealth)? {
        let probe = Self.anonymousEndpoint(endpoint)
        for candidate in await HostFallback.candidates(for: probe, resolver: resolver) {
            let client = RESTClient(endpoint: candidate, transport: makeAnonymousTransport(), config: config)
            if let health = try? await client.health(), health.ok {
                // The selected address keeps the endpoint's headers for the authenticated client that follows.
                let selected = HermesEndpoint(baseURL: candidate.baseURL, headers: endpoint.headers) ?? candidate
                return (selected, health)
            }
        }
        return nil
    }

    /// Signs in as `signIn` says and returns who the server says the user is.
    private func signIn(
        _ client: RESTClient, _ signIn: GatewaySignIn, secrets: ConnectionSecrets, providers: [String]
    ) async throws -> String {
        do {
            switch signIn {
            case .none:
                throw ConnectionTestFailure.signInRequired(providers: providers)
            case .password(let username):
                guard let password = secrets.password, !password.isEmpty else {
                    throw ConnectionTestFailure.missingSecret
                }
                try await client.passwordLogin(username: username, password: password)
            case .sessionToken, .browser:
                break
            }
            let user = try await client.currentUser()
            return user.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? user.userId
        } catch let failure as ConnectionTestFailure {
            throw failure
        } catch {
            throw Self.signInFailure(error)
        }
    }

    /// Opens the gateway WebSocket once, waits for the handshake and calls `gateway.capabilities`.
    /// Throws ``ConnectionTestFailure/webSocket(_:)``.
    public func webSocketLeg(
        _ endpoint: HermesEndpoint, transport: any WebSocketTransport,
        credential: @escaping GatewayCredentialProvider
    ) async throws {
        var config = GatewayClientConfig()
        config.connectTimeout = webSocketTimeout
        let client = GatewayClient(endpoint: endpoint, transport: transport, credentials: credential, config: config)
        let events = await client.events()
        await client.start()
        defer { Task { await client.stop() } }
        var outcome: ConnectionTestFailure? = .webSocket("no answer")
        for await event in events {
            guard case .state(let state) = event else { continue }
            if state == .connected {
                outcome = nil
                break
            }
            if let failure = Self.webSocketFailure(state) {
                outcome = failure
                break
            }
        }
        if let outcome { throw outcome }
        do {
            let _: GatewayCapabilitiesResult = try await client.call(
                "gateway.capabilities", params: EmptyParams(), timeout: webSocketTimeout)
        } catch {
            throw ConnectionTestFailure.webSocket("gateway.capabilities: \(error)")
        }
    }

    /// A client state that ends the WebSocket leg, as a failure. Nil while the first attempt is still running.
    static func webSocketFailure(_ state: GatewayConnectionState) -> ConnectionTestFailure? {
        switch state {
        case .waitingToReconnect: .webSocket("the connection closed during the handshake")
        case .failed: .wrongCredentials
        case .stopped: .webSocket("stopped")
        case .idle, .connecting, .connected: nil
        }
    }

    /// Reads health and status without signing in, so the form can show the right sign-in method.
    /// Nil when nothing usable answers.
    public func probe(_ endpoint: HermesEndpoint) async -> ServerProbe? {
        var config = RESTClientConfig()
        config.maxRateLimitRetries = 0
        let transport = makeAnonymousTransport()
        var client = RESTClient(endpoint: Self.anonymousEndpoint(endpoint), transport: transport, config: config)
        var adapted: HermesEndpoint?
        let health: ServerHealth
        do {
            health = try await client.health()
        } catch {
            guard Self.reachFailure(error).isHostRejected,
                let found = await reachByAddress(endpoint, config: config)
            else { return nil }
            adapted = found.endpoint
            health = found.health
            client = RESTClient(
                endpoint: Self.anonymousEndpoint(found.endpoint), transport: makeAnonymousTransport(), config: config)
        }
        guard health.ok else { return nil }
        let options = try? await SignInOptions.detect(using: client)
        var probe = ServerProbe(
            authRequired: health.authRequired ?? options?.authRequired ?? false,
            authProviders: options?.providers.map(\.name) ?? [], signIn: options)
        probe.adaptedEndpoint = adapted
        return probe
    }

    /// Maps a REST error from reaching the server to a form message.
    public static func reachFailure(_ error: any Error) -> ConnectionTestFailure {
        switch error {
        case RESTError.transport(let detail): .unreachable(detail)
        case RESTError.unexpectedContent, RESTError.decoding: .notHermes
        case RESTError.http(404, _): .notHermes
        case RESTError.http(let status, let detail): .server(status: status, detail: detail)
        case RESTError.unauthorized: .signInRequired(providers: [])
        case RESTError.rateLimited(let retryAfter): .rateLimited(retryAfter: retryAfter)
        default: .unreachable("\(error)")
        }
    }

    /// Maps a REST error from signing in to a form message.
    public static func signInFailure(_ error: any Error) -> ConnectionTestFailure {
        switch error {
        case RESTError.unauthorized, RESTError.http(403, _): .wrongCredentials
        default: reachFailure(error)
        }
    }
}
