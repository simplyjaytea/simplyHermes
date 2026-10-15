import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Signs in to one gateway connection and keeps it signed in.
///
/// Owns the REST client the rest of the app uses for this connection and installs its `401` hook:
/// - Browser sign-in: rotates the refresh token (`/auth/native/refresh`), stores the new pair in the Keychain before
///   using it, and coalesces concurrent refreshes.
/// - Password sign-in with "remember password" on (plan 2.3, opt-in): signs in again silently, at most once per
///   ``silentLoginInterval`` so a wrong stored password never hammers the 10-per-minute limit.
/// - Anything else: the user must sign in again (``GatewaySignInRequired``).
public actor GatewayAuthSession {
    /// The API client for this connection. Its auth and `401` hook are managed here.
    public nonisolated let client: RESTClient
    /// A client on the same transport (same cookies) without a `401` hook, for the auth endpoints themselves.
    private let authClient: RESTClient
    private let connectionID: UUID
    private let transport: any HTTPTransport
    private var settings: GatewaySettings
    private let credentials: any CredentialStore
    private let now: @Sendable () -> Double
    private var tokens: NativeTokens?
    private var refreshTask: Task<NativeTokens, any Error>?
    private var lastSilentLogin: Double?

    /// Refresh the access token when it expires within this many seconds.
    public let refreshMargin: Double
    /// Shortest time between two silent password sign-ins.
    public let silentLoginInterval: Double

    /// Creates a session. Call ``prepare()`` before the first request.
    public init(
        connectionID: UUID, settings: GatewaySettings, credentials: any CredentialStore,
        transport: any HTTPTransport = URLSessionHTTPTransport(), clock: any GatewayClock = SystemGatewayClock(),
        now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }, refreshMargin: Double = 60,
        silentLoginInterval: Double = 60
    ) {
        self.connectionID = connectionID
        self.transport = transport
        self.settings = settings
        self.credentials = credentials
        self.now = now
        self.refreshMargin = refreshMargin
        self.silentLoginInterval = silentLoginInterval
        var authConfig = RESTClientConfig()
        authConfig.maxRateLimitRetries = 0
        authClient = RESTClient(endpoint: settings.endpoint, transport: transport, clock: clock, config: authConfig)
        client = RESTClient(endpoint: settings.endpoint, transport: transport, clock: clock)
    }

    // MARK: - Lifecycle

    /// Loads stored credentials, sets the client's auth, installs the `401` hook, and refreshes an access token
    /// that is about to expire.
    public func prepare() async throws {
        await client.setReauthenticator { [weak self] in
            guard let self else { throw GatewaySignInRequired() }
            try await self.reauthenticate()
        }
        switch settings.signIn {
        case .browser:
            tokens = try loadTokens()
            if let tokens {
                await setAuth(.bearer(tokens.accessToken))
                _ = try? await validAccessToken()
            } else {
                importStoredCookies()
                await setAuth(.cookie)
            }
        case .sessionToken:
            if let token = try credentials.string(for: .sessionToken, connection: connectionID) {
                await setAuth(.sessionToken(token))
            }
        case .none, .password:
            await setAuth(.cookie)
        }
    }

    /// True when browser tokens are stored.
    public var hasBrowserTokens: Bool { tokens != nil }

    // MARK: - Sign in

    /// Finishes a browser sign-in: checks the redirect, redeems the code and stores the tokens.
    @discardableResult
    public func completeBrowserSignIn(_ request: NativeSignInRequest, redirect: URL) async throws -> NativeTokens {
        let code = try request.code(from: redirect)
        let fresh = try await authClient.nativeToken(code: code, verifier: request.pkce.verifier)
        try await store(fresh)
        settings.signIn = .browser(provider: request.provider ?? fresh.provider)
        return fresh
    }

    /// Finishes the web view fallback on a server without native sign-in: keeps its session cookies (in the
    /// transport and the Keychain). The server refreshes cookie sessions itself.
    public func completeWebSignIn(cookies: [HTTPCookie], provider: String?) async throws {
        let stored = cookies.map(StoredCookie.init)
        try credentials.set(try JSONEncoder().encode(stored), for: .webCookies, connection: connectionID)
        (transport as? any CookieImporting)?.importCookies(cookies)
        tokens = nil
        try? credentials.remove(.nativeTokens, connection: connectionID)
        settings.signIn = .browser(provider: provider)
        await setAuth(.cookie)
    }

    /// Signs in with the password form. With `remember`, the password goes to the Keychain for silent re-login;
    /// without it any stored password is removed.
    public func signInWithPassword(username: String, password: String, remember: Bool) async throws {
        try await authClient.passwordLogin(username: username, password: password)
        if remember {
            try credentials.setString(password, for: .gatewayPassword, connection: connectionID)
        } else {
            try credentials.remove(.gatewayPassword, connection: connectionID)
        }
        settings.signIn = .password(username: username)
        settings.remembersPassword = remember
        await setAuth(.cookie)
    }

    /// Signs out: forgets tokens and the stored password, and ends the cookie session on the server (best effort).
    public func signOut() async {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        try? credentials.remove(.nativeTokens, connection: connectionID)
        try? credentials.remove(.gatewayPassword, connection: connectionID)
        try? credentials.remove(.webCookies, connection: connectionID)
        try? await authClient.logout()
        await setAuth(.cookie)
    }

    // MARK: - Tokens

    /// The current access token, refreshed first when it is about to expire. Nil without browser sign-in.
    public func validAccessToken() async throws -> String? {
        guard let current = tokens else { return nil }
        guard current.expires(within: refreshMargin, now: now()) else { return current.accessToken }
        return try await refresh().accessToken
    }

    /// Rotates the refresh token. Concurrent callers share one request. A refused refresh token signs out.
    private func refresh() async throws -> NativeTokens {
        if let refreshTask { return try await refreshTask.value }
        guard let current = tokens else { throw GatewaySignInRequired() }
        let task = Task { [authClient] in try await authClient.nativeRefresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            try await store(fresh)
            return fresh
        } catch NativeSignInError.sessionExpired {
            tokens = nil
            try? credentials.remove(.nativeTokens, connection: connectionID)
            throw GatewaySignInRequired()
        }
    }

    /// The `401` hook. Throws ``GatewaySignInRequired`` when only the user can fix it.
    func reauthenticate() async throws {
        switch settings.signIn {
        case .browser:
            // Without tokens this is a web view cookie session: the server refreshes those itself, so a 401 means
            // the user must sign in again.
            guard tokens != nil else { throw GatewaySignInRequired() }
            _ = try await refresh()
        case .password(let username):
            try await silentPasswordLogin(username: username)
        case .none, .sessionToken:
            throw GatewaySignInRequired()
        }
    }

    private func silentPasswordLogin(username: String) async throws {
        guard settings.remembersPassword,
            let password = try credentials.string(for: .gatewayPassword, connection: connectionID)
        else { throw GatewaySignInRequired() }
        if let last = lastSilentLogin, now() - last < silentLoginInterval { throw GatewaySignInRequired() }
        lastSilentLogin = now()
        do {
            try await authClient.passwordLogin(username: username, password: password)
        } catch RESTError.unauthorized, RESTError.rateLimited {
            throw GatewaySignInRequired()
        }
    }

    // MARK: - WebSocket

    /// Credentials for ``GatewayClient``: a fresh single-use ticket per connect, minted with the current sign-in.
    /// `.reauthenticate` refreshes or signs in again first.
    public nonisolated func credentialProvider() -> GatewayCredentialProvider {
        { [self] request in
            if request == .reauthenticate { try await reauthenticate() }
            _ = try await validAccessToken()
            do {
                return .ticket(try await client.webSocketTicket().ticket)
            } catch RESTError.unauthorized {
                throw GatewaySignInRequired()
            }
        }
    }

    // MARK: - Storage

    private func importStoredCookies() {
        guard let data = try? credentials.data(for: .webCookies, connection: connectionID),
            let stored = try? JSONDecoder().decode([StoredCookie].self, from: data)
        else { return }
        (transport as? any CookieImporting)?.importCookies(stored.compactMap(\.cookie))
    }

    private func loadTokens() throws -> NativeTokens? {
        guard let data = try credentials.data(for: .nativeTokens, connection: connectionID) else { return nil }
        return try JSONDecoder().decode(NativeTokens.self, from: data)
    }

    /// Saves before use, so a crash never leaves only the already-rotated refresh token behind.
    private func store(_ fresh: NativeTokens) async throws {
        try credentials.set(try JSONEncoder().encode(fresh), for: .nativeTokens, connection: connectionID)
        tokens = fresh
        await client.setAuth(.bearer(fresh.accessToken))
    }

    private func setAuth(_ auth: RESTAuth) async {
        await client.setAuth(auth)
    }
}
