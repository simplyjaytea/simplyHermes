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

    /// Creates a value.
    public init(
        password: String? = nil, sessionToken: String? = nil, sshKey: StoredSSHKey? = nil, sshPassword: String? = nil
    ) {
        self.password = password
        self.sessionToken = sessionToken
        self.sshKey = sshKey
        self.sshPassword = sshPassword
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

    /// Short text for the progress row.
    public var title: String {
        switch self {
        case .reachingServer: "Reaching the server…"
        case .signingIn: "Signing in…"
        case .checkingServer: "Checking Hermes…"
        case .connectingSSH: "Connecting over SSH…"
        case .startingDashboard: "Starting Hermes on the server…"
        case .forwarding: "Opening the tunnel…"
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
                : "This server needs browser sign-in, which arrives in a later update. Paste a session token for now."
        case .wrongCredentials:
            "The server refused the sign-in. Check the user name and password or token."
        case .rateLimited(let retryAfter):
            retryAfter.map { "Too many sign-in attempts. Try again in \(Int($0)) seconds." }
                ?? "Too many sign-in attempts. Try again in a minute."
        case .server(let status, let detail):
            "The server answered \(status)\(detail.map { ": \($0)" } ?? ".")"
        case .missingSecret:
            "Enter the password, token or key first."
        case .hostKeyRejected:
            "You didn't trust the server's key, so the app disconnected."
        case .hostKeyChanged:
            "The server's key changed since you trusted it. This can mean someone is intercepting the connection."
        case .ssh(let detail), .invalidForm(let detail):
            detail
        }
    }
}

/// What the gateway says about sign-in before the user signs in.
public struct ServerProbe: Sendable, Equatable {
    /// True when the server needs a login.
    public var authRequired: Bool
    /// Login providers such as `basic`.
    public var authProviders: [String]

    /// Creates a value.
    public init(authRequired: Bool, authProviders: [String]) {
        self.authRequired = authRequired
        self.authProviders = authProviders
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

/// Tests a gateway connection over REST: health, status, sign-in, then a WebSocket ticket to prove chat will work.
public struct GatewayConnectionTester: ConnectionTesting {
    private let makeTransport: @Sendable () -> any HTTPTransport

    /// Creates a tester. `makeTransport` gives each test a fresh transport (its own cookies).
    public init(makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionHTTPTransport(timeout: 15) }) {
        self.makeTransport = makeTransport
    }

    public func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        guard case .gateway(let settings) = connection.kind else {
            throw ConnectionTestFailure.server(status: 0, detail: "not a gateway connection")
        }
        var auth = RESTAuth.cookie
        if case .sessionToken = settings.signIn {
            guard let token = secrets.sessionToken, !token.isEmpty else { throw ConnectionTestFailure.missingSecret }
            auth = .sessionToken(token)
        }
        var config = RESTClientConfig()
        config.maxRateLimitRetries = 0
        let client = RESTClient(endpoint: settings.endpoint, transport: makeTransport(), auth: auth, config: config)

        progress(.reachingServer)
        let health: ServerHealth
        do {
            health = try await client.health()
        } catch {
            throw Self.reachFailure(error)
        }
        guard health.ok else { throw ConnectionTestFailure.notHermes }
        let status = try? await client.status()
        var report = ConnectionTestReport(
            serverVersion: health.displayVersion ?? health.version, releaseDate: status?.releaseDate,
            authProviders: status?.authProviders ?? [])

        if health.authRequired ?? status?.authRequired ?? false {
            progress(.signingIn)
            do {
                switch settings.signIn {
                case .none:
                    throw ConnectionTestFailure.signInRequired(providers: report.authProviders)
                case .password(let username):
                    guard let password = secrets.password, !password.isEmpty else {
                        throw ConnectionTestFailure.missingSecret
                    }
                    try await client.passwordLogin(username: username, password: password)
                case .sessionToken:
                    break
                }
                let user = try await client.currentUser()
                report.signedInAs = user.displayName.flatMap { $0.isEmpty ? nil : $0 } ?? user.userId
                progress(.checkingServer)
                if case .password = settings.signIn { _ = try await client.webSocketTicket() }
            } catch let failure as ConnectionTestFailure {
                throw failure
            } catch {
                throw Self.signInFailure(error)
            }
        } else {
            progress(.checkingServer)
        }
        return report
    }

    /// Reads health and status without signing in, so the form can show the right sign-in method.
    /// Nil when nothing usable answers.
    public func probe(_ endpoint: HermesEndpoint) async -> ServerProbe? {
        var config = RESTClientConfig()
        config.maxRateLimitRetries = 0
        let client = RESTClient(endpoint: endpoint, transport: makeTransport(), config: config)
        guard let health = try? await client.health(), health.ok else { return nil }
        let status = try? await client.status()
        return ServerProbe(
            authRequired: health.authRequired ?? status?.authRequired ?? false,
            authProviders: status?.authProviders ?? [])
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
