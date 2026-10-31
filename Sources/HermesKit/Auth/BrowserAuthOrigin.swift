import Foundation

/// Diagnoses a browser sign-in's callback origin before the browser opens.
///
/// Hermes can advertise a callback URL whose host differs from the address the user entered: the gateway's
/// `public_url` (or its hostname) is used for the OAuth callback while the user started on the IP. A PKCE cookie set
/// on one origin is then invisible to the callback on the other, so sign-in fails with "Missing PKCE state cookie".
/// This helper compares the two origins without switching them automatically; a mismatch is reported, never silently
/// followed.
public struct BrowserAuthOrigin: Sendable, Equatable {
    /// The typed server origin as `scheme://host:port`, with the effective port.
    public struct Origin: Sendable, Equatable {
        public let scheme: String
        public let host: String
        public let port: Int

        /// The canonical origin string.
        public var origin: String { "\(scheme)://\(host):\(port)" }
    }

    /// The outcome of comparing the two origins.
    public enum Diagnosis: Sendable, Equatable {
        /// The callback origin matches, or there is no usable callback origin to compare.
        case ok
        /// The callback origin differs from the typed origin. Start browser sign-in from `callbackOrigin` instead.
        case callbackOriginMismatch(typedOrigin: String, callbackOrigin: String)
    }

    /// The effective port for a scheme.
    public static func effectivePort(scheme: String, port: Int?) -> Int {
        if let port { return port }
        return scheme.lowercased() == "https" ? 443 : 80
    }

    /// The typed origin, or nil when it is not a usable http(s) URL with a host.
    public static func typedOrigin(_ endpoint: HermesEndpoint) -> Origin? {
        let url = endpoint.baseURL
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        return Origin(scheme: scheme, host: host.lowercased(), port: effectivePort(scheme: scheme, port: url.port))
    }

    /// Strictly parses a callback URL. Returns nil for anything that is not a safe http(s) callback with the
    /// expected path, no userinfo and no fragment.
    public static func parseCallbackURL(_ raw: String) -> Origin? {
        guard let url = URL(string: raw) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        guard let host = url.host, !host.isEmpty else { return nil }
        if url.user != nil || url.password != nil { return nil }
        if url.fragment != nil { return nil }
        let path = url.path
        guard path == "/auth/callback" || path.hasPrefix("/auth/callback/") else { return nil }
        return Origin(scheme: scheme, host: host.lowercased(), port: effectivePort(scheme: scheme, port: url.port))
    }

    /// Extracts the callback origin from a `Location` header, using its `redirect_uri` query item. Returns nil when
    /// there is no usable callback URL.
    public static func callbackOrigin(from locationHeader: String?) -> Origin? {
        guard let locationHeader, !locationHeader.isEmpty else { return nil }
        guard let location = URL(string: locationHeader) else { return nil }
        let items = URLComponents(url: location, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard
            let redirectURI = items.first(where: { $0.name == "redirect_uri" })?.value,
            !redirectURI.isEmpty
        else { return nil }
        return parseCallbackURL(redirectURI)
    }

    /// Compares the typed origin with the callback origin advertised by the server.
    public static func diagnose(typed endpoint: HermesEndpoint, locationHeader: String?) -> Diagnosis {
        guard let typed = typedOrigin(endpoint) else { return .ok }
        guard let callback = callbackOrigin(from: locationHeader) else { return .ok }
        if callback == typed { return .ok }
        return .callbackOriginMismatch(typedOrigin: typed.origin, callbackOrigin: callback.origin)
    }

    /// Performs the anonymous preflight for a browser sign-in and returns its diagnosis. The request is sent on the
    /// supplied transport; an anonymous transport keeps it cookie-free and redirect-free. No credentials are logged.
    public static func preflight(
        typed endpoint: HermesEndpoint, provider: String?, native: Bool, transport: any HTTPTransport
    ) async throws -> Diagnosis {
        let url: URL
        if native {
            let request = NativeSignInRequest(endpoint: endpoint, provider: provider, port: 1)
            url = request.authorizeURL
        } else {
            let encodedProvider = (provider ?? "").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            url = endpoint.url(forPath: "/auth/login?provider=" + encodedProvider)
        }
        let anonEndpoint = GatewayConnectionTester.anonymousEndpoint(endpoint)
        var headers = anonEndpoint.headers
        headers["Accept"] = "application/json"
        let response = try await transport.send(HTTPRequest(method: "GET", url: url, headers: headers))
        return diagnose(typed: endpoint, locationHeader: response.headers["location"])
    }
}
