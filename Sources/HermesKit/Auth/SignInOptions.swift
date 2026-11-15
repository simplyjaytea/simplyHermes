/// How a user can sign in to a gateway, read from `/api/status` and `/api/auth/providers` (plan 2.3).
public struct SignInOptions: Sendable, Equatable {
    /// The ways to sign in, in the order the form offers them.
    public enum Method: String, Sendable, Equatable, CaseIterable {
        /// Browser sheet: native PKCE when the server offers it, else the in-app web view.
        case browser
        /// The in-app password form (`basic`-style providers).
        case password
        /// Paste or scan a session token.
        case sessionToken
    }

    /// True when the server needs a login.
    public var authRequired: Bool
    /// Login providers.
    public var providers: [AuthProviderInfo]
    /// Flows from `auth_flows`, such as `cookie` and `native_pkce`.
    public var flows: [String]

    /// Creates a value.
    public init(authRequired: Bool, providers: [AuthProviderInfo], flows: [String]) {
        self.authRequired = authRequired
        self.providers = providers
        self.flows = flows
    }

    /// True when `/auth/native/*` is available (RFC 8252 with PKCE).
    public var supportsNativePKCE: Bool { flows.contains("native_pkce") }

    /// Providers that sign in through a browser (OAuth, OIDC).
    public var browserProviders: [AuthProviderInfo] { providers.filter { $0.supportsPassword != true } }

    /// The first password provider, such as `basic`.
    public var passwordProvider: AuthProviderInfo? { providers.first { $0.supportsPassword == true } }

    /// The methods to offer. Empty when no login is needed. Browser sign-in needs native PKCE or a browser
    /// provider (the web view fallback); the password form needs a password provider; a token always works.
    public var methods: [Method] {
        guard authRequired else { return [] }
        var methods: [Method] = []
        if supportsNativePKCE || !browserProviders.isEmpty { methods.append(.browser) }
        if passwordProvider != nil { methods.append(.password) }
        methods.append(.sessionToken)
        return methods
    }

    /// The method the form selects first: browser for OAuth servers, the password form for password-only servers.
    public var recommended: Method? {
        guard authRequired else { return nil }
        if !browserProviders.isEmpty, methods.contains(.browser) { return .browser }
        if passwordProvider != nil { return .password }
        return methods.first
    }

    /// What the sign-in section shows. Every provider the server lists is reachable: one the app does not know
    /// (a custom `DashboardAuthProvider` plugin) is not a password provider, so it is a browser provider.
    public struct Offer: Sendable, Equatable {
        /// One "Continue with" button each. Includes providers of a type the app does not know.
        public var browserProviders: [AuthProviderInfo]
        /// The provider behind the user name and password fields, if any.
        public var passwordProvider: AuthProviderInfo?
        /// True when the server lists no provider but supports native sign-in, so one generic browser button helps.
        public var genericBrowser: Bool
        /// True when the server needs a login but names no way to sign in. The user needs a token or a server fix.
        public var offersNothing: Bool
    }

    /// The buttons and fields to show for these options.
    public var offer: Offer {
        Offer(
            browserProviders: browserProviders, passwordProvider: passwordProvider,
            genericBrowser: browserProviders.isEmpty && passwordProvider == nil && supportsNativePKCE,
            offersNothing: authRequired && providers.isEmpty && !supportsNativePKCE)
    }

    /// Reads the options. A server whose provider list fails still gets options from `/api/status`.
    public static func detect(using client: RESTClient) async throws -> SignInOptions {
        let status = try await client.status()
        var providers = (try? await client.authProviders()) ?? []
        if providers.isEmpty {
            providers = (status.authProviders ?? []).map {
                AuthProviderInfo(name: $0, supportsPassword: $0 == "basic")
            }
        }
        return SignInOptions(
            authRequired: status.authRequired ?? !providers.isEmpty, providers: providers,
            flows: status.authFlows ?? [])
    }
}
