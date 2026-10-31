import Foundation
import HermesKit
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A transport that records its request and answers one fixed response. It also records cookie imports, so a test can
/// prove the preflight never imports any.
final class RecordingAuthTransport: HTTPTransport, CookieImporting, @unchecked Sendable {
    struct Record {
        let headers: [String: String]
        let url: URL
    }

    private let lock = NSLock()
    private var records: [Record] = []
    private var imported: [[HTTPCookie]] = []
    private let response: HTTPResponse

    init(status: Int = 302, location: String? = nil, body: String = "{}") {
        var headers: [String: String] = ["Content-Type": "application/json"]
        if let location { headers["Location"] = location }
        response = HTTPResponse(status: status, headers: headers, body: Data(body.utf8))
    }

    var requests: [Record] { lock.withLock { records } }
    var cookieImports: [[HTTPCookie]] { lock.withLock { imported } }

    func importCookies(_ cookies: [HTTPCookie]) {
        lock.withLock { imported.append(cookies) }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { records.append(Record(headers: request.headers, url: request.url)) }
        return response
    }
}

@Suite struct BrowserAuthOriginTests {
    private let typedIP = HermesEndpoint(string: "http://100.64.150.77:9119")!
    private let typedHost = HermesEndpoint(string: "http://hostinger-vps.tailfa5476.ts.net:9119")!

    @Test func crossOriginCallbackIsReported() {
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: location)
        #expect(
            diagnosis
                == .callbackOriginMismatch(
                    typedOrigin: "http://100.64.150.77:9119",
                    callbackOrigin: "http://hostinger-vps.tailfa5476.ts.net:9119"))
    }

    @Test func matchingOriginPreservesTheFlow() {
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typedHost, locationHeader: location)
        #expect(diagnosis == .ok)
    }

    @Test func defaultPortMatches() {
        let typed = HermesEndpoint(string: "http://example.com")!
        let location = "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2Fexample.com%2Fauth%2Fcallback"
        #expect(BrowserAuthOrigin.diagnose(typed: typed, locationHeader: location) == .ok)
    }

    @Test func rejectsMalformedCallbackMetadata() {
        let cases = [
            // userinfo
            "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2Fuser%3Asecret%40example.com%2Fauth%2Fcallback",
            // fragment
            "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2Fexample.com%2Fauth%2Fcallback%23frag",
            // wrong path
            "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2Fexample.com%2Foauth%2Fcallback",
            // non-http scheme
            "https://idp.example.com/authorize?redirect_uri=ftp%3A%2F%2Fexample.com%2Fauth%2Fcallback",
            // missing redirect_uri
            "https://idp.example.com/authorize?state=abc",
            // not a URL
            "not a url",
        ]
        for location in cases {
            #expect(
                BrowserAuthOrigin.diagnose(typed: typedHost, locationHeader: location) == .ok,
                "malformed metadata should not be treated as a callback origin: \(location)")
        }
    }

    @Test func noLocationOrRedirectUriPreservesTheFlow() {
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: nil) == .ok)
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: "") == .ok)
        let location = "https://idp.example.com/authorize?state=abc"
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: location) == .ok)
    }

    @Test func parseCallbackURLRejectsPublicCallbackHostMetadata() {
        // A Location whose own host is the identity provider must not be mistaken for the callback origin.
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let callback = BrowserAuthOrigin.callbackOrigin(from: location)
        #expect(callback?.host == "hostinger-vps.tailfa5476.ts.net")
        #expect(callback?.host != "portal.nousresearch.com")
    }

    @Test func preflightIsAnonymousAndDoesNotFollowRedirects() async throws {
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let transport = RecordingAuthTransport(status: 302, location: location)
        let diagnosis = try await BrowserAuthOrigin.preflight(
            typed: typedIP, provider: "nous", native: true, transport: transport)
        #expect(
            diagnosis
                == .callbackOriginMismatch(
                    typedOrigin: "http://100.64.150.77:9119",
                    callbackOrigin: "http://hostinger-vps.tailfa5476.ts.net:9119"))
        #expect(transport.requests.count == 1, "preflight must not follow the redirect")
        #expect(transport.cookieImports.isEmpty, "preflight must not import cookies")
        let request = try #require(transport.requests.first)
        let allowed: Set<String> = ["host", "x-forwarded-host", "accept"]
        for (name, value) in request.headers {
            #expect(allowed.contains(name.lowercased()), "preflight sent \\(name)")
            #expect(!value.lowercased().contains("secret"))
        }
    }

    @Test func preflightPreservesFlowWhenThereIsNoCallbackOrigin() async throws {
        let transport = RecordingAuthTransport(status: 200, location: nil)
        let diagnosis = try await BrowserAuthOrigin.preflight(
            typed: typedHost, provider: nil, native: false, transport: transport)
        #expect(diagnosis == .ok)
        #expect(transport.requests.count == 1)
    }
}
