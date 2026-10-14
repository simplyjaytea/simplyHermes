import Foundation

/// Where a Hermes server listens: a base URL with an optional path prefix, plus extra headers.
///
/// Gateway mode and SSH mode both produce one of these, so REST and WebSocket code can share it. The base URL is
/// `http` or `https`, with an optional path prefix such as `/hermes` behind a reverse proxy. It has no query, no
/// fragment and no user info.
public struct HermesEndpoint: Sendable, Hashable, Codable {
    /// The base URL: scheme `http` or `https`, host, optional port and optional path prefix.
    public let baseURL: URL
    /// Extra headers sent on every request, for example `Host` when a local forwarder sits in front.
    public let headers: [String: String]

    /// Creates an endpoint. Returns nil unless `baseURL` is an absolute `http` or `https` URL with a host and no
    /// query, fragment or user info.
    public init?(baseURL: URL, headers: [String: String] = [:]) {
        guard let components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = components.host, !host.isEmpty,
            components.query == nil, components.fragment == nil, components.user == nil, components.password == nil
        else { return nil }
        self.baseURL = baseURL
        self.headers = headers
    }

    /// Parses `string` as a base URL. Returns nil when it is not a valid endpoint.
    public init?(string: String, headers: [String: String] = [:]) {
        guard let url = URL(string: string) else { return nil }
        self.init(baseURL: url, headers: headers)
    }

    /// The URL for `path` below the base URL, keeping the base URL's path prefix.
    ///
    /// Joins with or without a prefix and never produces a double slash. A trailing slash on `path` is kept. A query
    /// on `path` is kept as written, so pass it already percent-encoded: `"/api/sessions?profile=ops"`. Other
    /// characters in `path` are percent-encoded, so pass raw segments such as session ids.
    public func url(forPath path: String) -> URL {
        let (pathPart, query) = Self.splitQuery(path)
        var components = baseComponents
        components.percentEncodedPath = Self.joinedPath(prefix: basePrefixSegments, requestPath: pathPart)
        components.percentEncodedQuery = query.isEmpty ? nil : query
        return components.url ?? baseURL
    }

    /// The WebSocket URL for `path`: `ws` for `http`, `wss` for `https`.
    ///
    /// Adds `token` and `ticket` as query items when given. The token is the session token (`?token=`). The ticket
    /// is the single-use value from `POST /api/auth/ws-ticket` (`?ticket=`). Never sets an `Origin` header.
    public func webSocketURL(path: String, token: String? = nil, ticket: String? = nil) -> URL {
        let (pathPart, pathQuery) = Self.splitQuery(path)
        var components = baseComponents
        components.scheme = baseURL.scheme?.lowercased() == "https" ? "wss" : "ws"
        components.percentEncodedPath = Self.joinedPath(prefix: basePrefixSegments, requestPath: pathPart)
        var pairs = pathQuery.isEmpty ? [] : [pathQuery]
        if let token { pairs.append("token=" + Self.encodeQueryValue(token)) }
        if let ticket { pairs.append("ticket=" + Self.encodeQueryValue(ticket)) }
        components.percentEncodedQuery = pairs.isEmpty ? nil : pairs.joined(separator: "&")
        return components.url ?? baseURL
    }

    /// Headers for a request: the endpoint's extra headers, plus `X-Hermes-Session-Token` when a token is given.
    public func requestHeaders(sessionToken: String? = nil) -> [String: String] {
        var result = headers
        if let sessionToken { result["X-Hermes-Session-Token"] = sessionToken }
        return result
    }

    /// A key for deduplicating endpoints: lowercased scheme and host, default port removed, trailing slash removed.
    /// Two endpoints with the same key reach the same server. Headers are not part of the key.
    public var normalizedKey: String {
        var components = baseComponents
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        if let port = components.port, port == Self.defaultPort(for: components.scheme) {
            components.port = nil
        }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path
        return components.string ?? baseURL.absoluteString
    }

    // MARK: - Helpers

    private var baseComponents: URLComponents {
        URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
    }

    /// Non-empty path segments of the base URL, already percent-encoded.
    private var basePrefixSegments: [String] {
        baseComponents.percentEncodedPath.split(separator: "/").map(String.init)
    }

    private static func splitQuery(_ path: String) -> (path: String, query: String) {
        guard let index = path.firstIndex(of: "?") else { return (path, "") }
        return (String(path[..<index]), String(path[path.index(after: index)...]))
    }

    /// Joins the prefix (already encoded) with the request path (raw segments, encoded here).
    private static func joinedPath(prefix: [String], requestPath: String) -> String {
        let segments = requestPath.split(separator: "/").map { segment in
            String(segment).addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? String(segment)
        }
        let trailingSlash = requestPath.hasSuffix("/") && !segments.isEmpty ? "/" : ""
        return "/" + (prefix + segments).joined(separator: "/") + trailingSlash
    }

    private static func encodeQueryValue(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: queryValueAllowed) ?? value
    }

    private static func defaultPort(for scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "http", "ws": 80
        case "https", "wss": 443
        default: nil
        }
    }

    /// RFC 3986 unreserved characters. Only these stay as written in a query value, so a token needs no escaping.
    private static let unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

    private static var queryValueAllowed: CharacterSet { CharacterSet(charactersIn: unreserved) }

    /// RFC 3986 `pchar` without `%`. A literal `%` is escaped too, so raw segments and encoded input are not mixed up.
    private static var pathSegmentAllowed: CharacterSet { CharacterSet(charactersIn: unreserved + "!$&'()*+,;=:@") }
}

extension HermesEndpoint {
    /// Decodes an endpoint and validates it, so an invalid value cannot be stored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let url = try container.decode(URL.self, forKey: .baseURL)
        let headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        guard let endpoint = HermesEndpoint(baseURL: url, headers: headers) else {
            throw DecodingError.dataCorruptedError(
                forKey: .baseURL, in: container, debugDescription: "not an http or https base URL")
        }
        self = endpoint
    }

    /// Encodes the base URL and the headers.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(baseURL, forKey: .baseURL)
        try container.encode(headers, forKey: .headers)
    }

    enum CodingKeys: String, CodingKey {
        case baseURL, headers
    }
}
