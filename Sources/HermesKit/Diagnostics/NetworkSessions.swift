import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Makes every `URLSession` the app uses (WP-7, AT-2b). Each session is built here, so each one can be counted. In debug
/// builds a counting `URLProtocol` is put first in the configuration: it sees each request the session starts, counts it,
/// and declines it, so the request is loaded as it would be without the counter. A Linux test fails when `URLSession(` or
/// `URLSession.shared` appears anywhere else in the sources, so a session cannot be made outside this file.
public enum NetworkSessions {
    /// Builds a session. In release builds this is `URLSession(configuration:delegate:delegateQueue:)`.
    public static func make(
        configuration: URLSessionConfiguration, delegate: (any URLSessionDelegate)? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        #if DEBUG
            configuration.protocolClasses = [CountingProtocol.self] + (configuration.protocolClasses ?? [])
        #endif
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: delegateQueue)
    }
}

#if DEBUG
    /// Counts each request a factory session starts, and never handles it: `canInit` returns false, so loading continues
    /// in the next protocol. `canInit` may run more than once for one request, so the count is a lower bound on
    /// requests and only ever over-counts; the tests check for zero and for at least one.
    class CountingProtocol: URLProtocol {
        override class func canInit(with request: URLRequest) -> Bool {
            NetworkTrap.record("intercepted")
            return false
        }

        override class func canonicalRequest(for request: URLRequest) -> URLRequest {
            request
        }
    }
#endif
