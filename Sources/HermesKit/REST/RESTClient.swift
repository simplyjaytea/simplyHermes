import Foundation

/// How REST calls prove who they are.
public enum RESTAuth: Sendable, Equatable {
    /// Gateway mode: the session cookies the transport holds after ``RESTClient/passwordLogin(username:password:)``.
    case cookie
    /// SSH mode: the per-process token, sent as `X-Hermes-Session-Token`.
    case sessionToken(String)
    /// Native sign-in (RFC 8252): the access token from `/auth/native/token`, sent as `Authorization: Bearer`.
    case bearer(String)
}

/// Errors from ``RESTClient``.
public enum RESTError: Error, Sendable, Equatable {
    /// `401` and re-authentication did not help (or there is no hook). The user must sign in.
    case unauthorized
    /// `429` after all retries. `retryAfter` is the server's hint in seconds.
    case rateLimited(retryAfter: Double?)
    /// Another non-2xx status. `detail` is the server's `detail` message when it sent one.
    case http(status: Int, detail: String?)
    /// A `2xx` that is not JSON, for example the login page a dashboard serves instead of an API answer.
    case unexpectedContent(contentType: String?)
    /// No response arrived.
    case transport(String)
    /// The response body did not match the expected type.
    case decoding(String)
}

/// Tuning knobs for ``RESTClient``.
public struct RESTClientConfig: Sendable {
    /// Retries after a `429` before giving up.
    public var maxRateLimitRetries = 3
    /// Wait before the first `429` retry when the server sends no `Retry-After`; doubles each time.
    public var rateLimitBase: Double = 2
    /// Longest wait between `429` retries in seconds.
    public var rateLimitCap: Double = 60

    /// Creates the default configuration.
    public init() {}
}

/// Hook called after a `401`: sign in again (cookie mode) or fetch a fresh token. Throw to give up.
public typealias RESTReauthenticator = @Sendable () async throws -> Void

/// A typed HTTP client for the dashboard REST API.
///
/// Joins paths onto the endpoint's base URL (prefix kept), adds the `?profile=` scope, retries `429` with
/// backoff and calls a re-authentication hook once on `401`.
public actor RESTClient {
    private let endpoint: HermesEndpoint
    private let transport: any HTTPTransport
    private var auth: RESTAuth
    private let clock: any GatewayClock
    private let config: RESTClientConfig
    private var reauthenticator: RESTReauthenticator?
    private var reauthTask: Task<Void, any Error>?

    /// The profile added as `?profile=` to scoped calls. Nil means the server's active profile.
    public var profile: String?

    /// Creates a client.
    public init(
        endpoint: HermesEndpoint, transport: any HTTPTransport, auth: RESTAuth = .cookie, profile: String? = nil,
        clock: any GatewayClock = SystemGatewayClock(), config: RESTClientConfig = RESTClientConfig(),
        reauthenticate: RESTReauthenticator? = nil
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.auth = auth
        self.profile = profile
        self.clock = clock
        self.config = config
        self.reauthenticator = reauthenticate
    }

    /// Sets the profile used for scoped calls.
    public func setProfile(_ name: String?) { profile = name }

    /// Replaces how calls authenticate, for example after a bearer token was rotated.
    public func setAuth(_ auth: RESTAuth) { self.auth = auth }

    /// Sets or clears the re-authentication hook.
    public func setReauthenticator(_ hook: RESTReauthenticator?) { reauthenticator = hook }

    // MARK: - Typed calls

    /// `GET` and decode the JSON body.
    public func get<Result: Decodable & Sendable>(
        _ path: String, query: [URLQueryItem] = [], scoped: Bool = true, as type: Result.Type = Result.self
    ) async throws -> Result {
        try decode(try await send("GET", path, query: query, scoped: scoped))
    }

    /// Sends `body` as JSON with `method` and decodes the JSON answer.
    public func send<Result: Decodable & Sendable>(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable & Sendable)? = nil,
        scoped: Bool = true, as type: Result.Type = Result.self
    ) async throws -> Result {
        try decode(try await send(method, path, query: query, body: body, scoped: scoped))
    }

    /// Sends a request and returns the raw successful response, after retries and re-authentication.
    ///
    /// Fails with ``RESTError/unexpectedContent(contentType:)`` for a `2xx` HTML page. Use ``sendRaw(_:_:query:body:scoped:)``
    /// for endpoints that return files.
    public func send(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable & Sendable)? = nil,
        scoped: Bool = true
    ) async throws -> HTTPResponse {
        let response = try await sendRaw(method, path, query: query, body: body, scoped: scoped)
        if let type = response.headers["content-type"]?.lowercased(), type.contains("text/html") {
            throw RESTError.unexpectedContent(contentType: type)
        }
        return response
    }

    /// Like ``send(_:_:query:body:scoped:)`` but accepts any content type.
    public func sendRaw(
        _ method: String, _ path: String, query: [URLQueryItem] = [], body: (any Encodable & Sendable)? = nil,
        scoped: Bool = true
    ) async throws -> HTTPResponse {
        let encoded: Data? = try body.map { try Self.encoder.encode(AnyEncodable($0)) }
        var retriedAuth = false
        var rateLimitRetries = 0
        while true {
            let request = makeRequest(method, path, scopedQuery(query, scoped), encoded)
            let response: HTTPResponse
            do {
                response = try await transport.send(request)
            } catch let error as RESTError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw RESTError.transport("\(error)")
            }
            switch response.status {
            case 200..<300:
                return response
            case 401:
                guard !retriedAuth, reauthenticator != nil else { throw RESTError.unauthorized }
                retriedAuth = true
                do { try await reauthenticate() } catch { throw RESTError.unauthorized }
            case 429:
                let hint = response.headers["retry-after"].flatMap(Double.init)
                guard rateLimitRetries < config.maxRateLimitRetries else {
                    throw RESTError.rateLimited(retryAfter: hint)
                }
                let backoff = min(config.rateLimitCap, config.rateLimitBase * pow(2, Double(rateLimitRetries)))
                rateLimitRetries += 1
                try await clock.sleep(seconds: min(config.rateLimitCap, max(hint ?? 0, backoff)))
            default:
                throw RESTError.http(status: response.status, detail: Self.detail(in: response.body))
            }
        }
    }

    // MARK: - Helpers

    private func scopedQuery(_ query: [URLQueryItem], _ scoped: Bool) -> [URLQueryItem] {
        guard scoped, let profile, !query.contains(where: { $0.name == "profile" }) else { return query }
        return query + [URLQueryItem(name: "profile", value: profile)]
    }

    private func makeRequest(_ method: String, _ path: String, _ items: [URLQueryItem], _ body: Data?) -> HTTPRequest {
        let url = endpoint.url(forPath: Self.pathWithQuery(path, items))
        var headers = endpoint.headers
        headers["Accept"] = "application/json"
        if body != nil { headers["Content-Type"] = "application/json" }
        switch auth {
        case .cookie: break
        case .sessionToken(let token): headers["X-Hermes-Session-Token"] = token
        case .bearer(let token): headers["Authorization"] = "Bearer \(token)"
        }
        return HTTPRequest(method: method, url: url, headers: headers, body: body)
    }

    private static func pathWithQuery(_ path: String, _ items: [URLQueryItem]) -> String {
        guard !items.isEmpty else { return path }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+#")
        let pairs = items.map { item -> String in
            let name = item.name.addingPercentEncoding(withAllowedCharacters: allowed) ?? item.name
            guard let value = item.value else { return name }
            return name + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        return path + (path.contains("?") ? "&" : "?") + pairs.joined(separator: "&")
    }

    /// Runs the hook once even when several calls hit `401` together.
    private func reauthenticate() async throws {
        if let reauthTask {
            try await reauthTask.value
            return
        }
        guard let hook = reauthenticator else { throw RESTError.unauthorized }
        let task = Task { try await hook() }
        reauthTask = task
        defer { reauthTask = nil }
        try await task.value
    }

    private func decode<Result: Decodable>(_ response: HTTPResponse) throws -> Result {
        do {
            return try Self.decoder.decode(Result.self, from: response.body)
        } catch {
            throw RESTError.decoding("\(error)")
        }
    }

    /// Decodes snake_case keys into camelCase properties. Keys that are already camelCase stay as they are.
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// Encodes camelCase properties as snake_case keys.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private static func detail(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        if let text = object["detail"] as? String { return text }
        if let text = object["error"] as? String { return text }
        return nil
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: any Encoder) throws { try value.encode(to: encoder) }
}
