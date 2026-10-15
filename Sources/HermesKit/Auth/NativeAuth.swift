import Foundation

/// Tokens from `/auth/native/token` and `/auth/native/refresh`. Stored in the Keychain as
/// ``CredentialKind/nativeTokens``.
public struct NativeTokens: Sendable, Equatable, Codable {
    /// Bearer token for REST calls and WebSocket ticket minting.
    public var accessToken: String
    /// Refresh token. Every refresh returns a new one; always keep the newest.
    public var refreshToken: String
    /// Unix seconds when the access token expires.
    public var expiresAt: Double
    /// Login provider, such as `basic` or `nous`. Sent back on refresh.
    public var provider: String?
    /// The signed-in user id.
    public var userID: String?

    /// Creates tokens.
    public init(
        accessToken: String, refreshToken: String, expiresAt: Double, provider: String? = nil, userID: String? = nil
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.provider = provider
        self.userID = userID
    }

    enum CodingKeys: String, CodingKey {
        case provider
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresAt = "expires_at"
        case userID = "user_id"
    }

    /// True when the access token expires within `margin` seconds of `now`.
    public func expires(within margin: Double, now: Double) -> Bool {
        expiresAt - now <= margin
    }
}

/// Errors of the native sign-in flow.
public enum NativeSignInError: Error, Sendable, Equatable {
    /// The redirect carried a different `state`: possibly forged. Start again.
    case stateMismatch
    /// The redirect carried no code.
    case missingCode
    /// The server sent an OAuth error on the redirect.
    case server(String)
    /// The code was refused (wrong verifier, expired, or used twice). Start again.
    case codeRejected
    /// The refresh token is no longer valid: sign in again.
    case sessionExpired
    /// The user closed the sign-in sheet.
    case cancelled
}

/// Builds and checks the URLs of one RFC 8252 sign-in. The flow:
///
/// 1. Open ``authorizeURL`` in the browser sheet. The server shows its login page (password providers) or sends the
///    browser to the identity provider.
/// 2. The server redirects the browser to ``redirectURI`` (`http://127.0.0.1:<port>/cb?code=…&state=…`).
/// 3. ``code(from:)`` checks `state` and returns the code; ``RESTClient/nativeToken(code:verifier:)`` redeems it.
public struct NativeSignInRequest: Sendable, Equatable {
    /// The gateway.
    public let endpoint: HermesEndpoint
    /// Provider to use. Nil lets the server pick the only one or show a chooser.
    public let provider: String?
    /// The loopback redirect, `http://127.0.0.1:<port>/cb`.
    public let redirectURI: String
    /// PKCE pair and state.
    public let pkce: PKCEPair

    /// The path the loopback receiver answers.
    public static let callbackPath = "/cb"

    /// Creates a request for a loopback receiver on `port`.
    public init(endpoint: HermesEndpoint, provider: String? = nil, port: Int, pkce: PKCEPair = .generate()) {
        self.endpoint = endpoint
        self.provider = provider
        self.redirectURI = "http://127.0.0.1:\(port)\(Self.callbackPath)"
        self.pkce = pkce
    }

    /// `GET /auth/native/authorize?…` on the gateway, prefix kept.
    public var authorizeURL: URL {
        var items = [
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: PKCEPair.method),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "state", value: pkce.state),
        ]
        if let provider, !provider.isEmpty { items.insert(URLQueryItem(name: "provider", value: provider), at: 0) }
        var components = URLComponents()
        components.queryItems = items
        // `+` is legal in a query but servers read it as a space; encode it.
        let query = (components.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B")
        return endpoint.url(forPath: "/auth/native/authorize?" + query)
    }

    /// True when `url` is the loopback redirect of this request.
    public func isRedirect(_ url: URL) -> Bool {
        guard let redirect = URL(string: redirectURI) else { return false }
        return url.scheme == "http" && url.host == redirect.host && url.port == redirect.port
            && url.path == redirect.path
    }

    /// The code from the redirect `url`, after checking `state`.
    public func code(from url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") { throw NativeSignInError.server(value("error_description") ?? error) }
        guard value("state") == pkce.state else { throw NativeSignInError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw NativeSignInError.missingCode }
        return code
    }
}

private struct NativeTokenBody: Encodable, Sendable {
    var code: String
    var codeVerifier: String
}

private struct NativeRefreshBody: Encodable, Sendable {
    var refreshToken: String
    var provider: String
}

extension RESTClient {
    /// `POST /auth/native/token`: redeems the loopback code with the PKCE verifier. The code is single use.
    public func nativeToken(code: String, verifier: String) async throws -> NativeTokens {
        do {
            return try await send(
                "POST", "/auth/native/token", body: NativeTokenBody(code: code, codeVerifier: verifier), scoped: false,
                as: NativeTokensWire.self
            ).tokens
        } catch RESTError.http(400, _) {
            throw NativeSignInError.codeRejected
        }
    }

    /// `POST /auth/native/refresh`: rotates the refresh token. Throws ``NativeSignInError/sessionExpired`` when the
    /// server refuses it (sign in again); other failures (503, network) are worth a later retry.
    public func nativeRefresh(_ tokens: NativeTokens) async throws -> NativeTokens {
        do {
            return try await send(
                "POST", "/auth/native/refresh",
                body: NativeRefreshBody(refreshToken: tokens.refreshToken, provider: tokens.provider ?? ""),
                scoped: false, as: NativeTokensWire.self
            ).tokens
        } catch RESTError.unauthorized, RESTError.http(400, _) {
            throw NativeSignInError.sessionExpired
        }
    }
}

/// The wire shape, decoded by ``RESTClient``'s snake-case decoder.
private struct NativeTokensWire: Decodable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Double
    var provider: String?
    var userId: String?

    var tokens: NativeTokens {
        NativeTokens(
            accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt, provider: provider,
            userID: userId)
    }
}
