import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One HTTP request, independent of `URLSession` so tests can script the server.
public struct HTTPRequest: Sendable, Equatable {
    /// `GET`, `POST`, `PUT`, `PATCH` or `DELETE`.
    public var method: String
    /// The full URL, query included.
    public var url: URL
    /// Request headers.
    public var headers: [String: String]
    /// The body, if any.
    public var body: Data?

    /// Creates a request.
    public init(method: String, url: URL, headers: [String: String] = [:], body: Data? = nil) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

/// One HTTP response.
public struct HTTPResponse: Sendable, Equatable {
    /// The status code.
    public var status: Int
    /// Response headers with lowercased names.
    public var headers: [String: String]
    /// The body.
    public var body: Data

    /// Creates a response. Header names are lowercased.
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        self.body = body
    }
}

/// Sends HTTP requests. The app uses ``URLSessionHTTPTransport``.
public protocol HTTPTransport: Sendable {
    /// Sends `request` and returns the response for any status code. Throws only when no response arrived.
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// Sends requests with `URLSession`. Keeps login cookies in its own cookie store and does not follow redirects, so a
/// login redirect shows up as the `3xx` it is.
public final class URLSessionHTTPTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let redirectBlocker = RedirectBlocker()

    /// Creates a transport with an ephemeral session (its own cookie jar, nothing written to disk).
    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration, delegate: redirectBlocker, delegateQueue: nil)
    }

    /// Sends the request.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw RESTError.transport("not an HTTP response") }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return HTTPResponse(status: http.statusCode, headers: headers, body: data)
    }
}

private final class RedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
