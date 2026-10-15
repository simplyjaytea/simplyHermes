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

/// A transport that can take cookies from elsewhere, such as the in-app sign-in web view.
public protocol CookieImporting: Sendable {
    /// Adds cookies to the transport's store.
    func importCookies(_ cookies: [HTTPCookie])
}

/// Sends requests with `URLSession`. Keeps login cookies in its own cookie store and does not follow redirects, so a
/// login redirect shows up as the `3xx` it is.
public final class URLSessionHTTPTransport: HTTPTransport, CookieImporting, @unchecked Sendable {
    private let session: URLSession
    private let redirectBlocker = RedirectBlocker()
    private let cookies = CookieJar()

    /// Creates a transport with an ephemeral session (its own cookie jar, nothing written to disk).
    public init(timeout: TimeInterval = 30) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout
        configuration.httpShouldSetCookies = true
        #if !canImport(Darwin)
            // swift-corelibs-foundation gives an ephemeral session no cookie store.
            if configuration.httpCookieStorage == nil { configuration.httpCookieStorage = HTTPCookieStorage.shared }
        #endif
        configuration.httpCookieAcceptPolicy = .always
        session = URLSession(configuration: configuration, delegate: redirectBlocker, delegateQueue: nil)
    }

    /// Adds cookies, for example the session cookies of a web view sign-in.
    public func importCookies(_ cookies: [HTTPCookie]) {
        #if canImport(Darwin)
            for cookie in cookies { session.configuration.httpCookieStorage?.setCookie(cookie) }
        #else
            self.cookies.store(cookies)
        #endif
    }

    /// Sends the request.
    public func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        #if !canImport(Darwin)
            for (name, value) in HTTPCookie.requestHeaderFields(with: cookies.cookies(for: request.url)) {
                urlRequest.setValue(value, forHTTPHeaderField: name)
            }
        #endif
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw RESTError.transport("not an HTTP response") }
        #if !canImport(Darwin)
            let stringHeaders = Dictionary(
                uniqueKeysWithValues: http.allHeaderFields.compactMap { pair -> (String, String)? in
                    guard let key = pair.key as? String, let value = pair.value as? String else { return nil }
                    return (key, value)
                })
            cookies.store(HTTPCookie.cookies(withResponseHeaderFields: stringHeaders, for: request.url))
        #endif
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

/// A minimal cookie jar for platforms whose `URLSession` keeps none.
private final class CookieJar: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: HTTPCookie] = [:]

    func store(_ cookies: [HTTPCookie]) {
        lock.withLock {
            for cookie in cookies {
                let key = cookie.domain + cookie.path + cookie.name
                if let expires = cookie.expiresDate, expires < Date() {
                    stored[key] = nil
                } else {
                    stored[key] = cookie
                }
            }
        }
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        lock.withLock {
            Array(stored.values).filter {
                $0.domain.isEmpty || url.host == $0.domain || url.host?.hasSuffix($0.domain) == true
            }
        }
    }
}
