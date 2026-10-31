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
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: location, responseStatus: 302)
        #expect(
            diagnosis
                == .callbackOriginMismatch(
                    typedOrigin: "http://100.64.150.77:9119",
                    callbackOrigin: "http://hostinger-vps.tailfa5476.ts.net:9119",
                    suggestedStartingURL: "http://hostinger-vps.tailfa5476.ts.net:9119"))
    }

    @Test func matchingOriginPreservesTheFlow() {
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typedHost, locationHeader: location, responseStatus: 302)
        #expect(diagnosis == .ok)
    }

    @Test func defaultPortMatches() {
        let typed = HermesEndpoint(string: "http://example.com")!
        let location = "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2Fexample.com%2Fauth%2Fcallback"
        #expect(BrowserAuthOrigin.diagnose(typed: typed, locationHeader: location, responseStatus: 302) == .ok)
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
                BrowserAuthOrigin.diagnose(typed: typedHost, locationHeader: location, responseStatus: 302) == .ok,
                "malformed metadata should not be treated as a callback origin: \(location)")
        }
    }

    @Test func noLocationOrRedirectUriPreservesTheFlow() {
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: nil, responseStatus: 302) == .ok)
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: "", responseStatus: 302) == .ok)
        let location = "https://idp.example.com/authorize?state=abc"
        #expect(BrowserAuthOrigin.diagnose(typed: typedIP, locationHeader: location, responseStatus: 302) == .ok)
    }

    @Test func parseCallbackURLRejectsPublicCallbackHostMetadata() {
        // A Location whose own host is the identity provider must not be mistaken for the callback origin.
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let callback = BrowserAuthOrigin.callbackOrigin(from: location, expectedPath: "/auth/callback")
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
                    callbackOrigin: "http://hostinger-vps.tailfa5476.ts.net:9119",
                    suggestedStartingURL: "http://hostinger-vps.tailfa5476.ts.net:9119"))
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

    @Test func preflightIgnoresLocationOnNonRedirectStatus() async throws {
        let location =
            "https://portal.nousresearch.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fauth%2Fcallback"
        let transport = RecordingAuthTransport(status: 200, location: location)
        let diagnosis = try await BrowserAuthOrigin.preflight(
            typed: typedIP, provider: "nous", native: true, transport: transport)
        #expect(diagnosis == .ok)
    }

    @Test func reverseProxyPrefixIsPreservedAndExact() {
        let typed = HermesEndpoint(string: "http://100.64.150.77:9119/hermes")!
        let matchingLocation =
            "https://portal.example.com/authorize?redirect_uri=http%3A%2F%2Fproxy.example.com%3A9119%2Fhermes%2Fauth%2Fcallback"
        #expect(
            BrowserAuthOrigin.diagnose(
                typed: typed, locationHeader: matchingLocation, responseStatus: 302) == .ok)

        let mismatchLocation =
            "https://portal.example.com/authorize?redirect_uri=http%3A%2F%2Fhostinger-vps.tailfa5476.ts.net%3A9119%2Fhermes%2Fauth%2Fcallback"
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typed, locationHeader: mismatchLocation, responseStatus: 302)
        #expect(
            diagnosis
                == .callbackOriginMismatch(
                    typedOrigin: "http://100.64.150.77:9119",
                    callbackOrigin: "http://hostinger-vps.tailfa5476.ts.net:9119",
                    suggestedStartingURL: "http://hostinger-vps.tailfa5476.ts.net:9119/hermes"))

        // A suffix or subpath is not the callback route.
        let suffixLocation =
            "https://portal.example.com/authorize?redirect_uri=http%3A%2F%2Fother.example.com%3A9119%2Fhermes%2Fauth%2Fcallback%2Fextra"
        #expect(
            BrowserAuthOrigin.diagnose(
                typed: typed, locationHeader: suffixLocation, responseStatus: 302) == .ok)
    }

    @Test func unusableCallbackAdviceIsWithheld() {
        // A public HTTP callback origin is not a usable starting URL under ConnectionAddress.
        let typed = HermesEndpoint(string: "http://100.64.150.77:9119")!
        let location =
            "https://portal.example.com/authorize?redirect_uri=http%3A%2F%2Fpublic.example.com%2Fauth%2Fcallback"
        #expect(BrowserAuthOrigin.diagnose(typed: typed, locationHeader: location, responseStatus: 302) == .ok)
    }

    @Test func ipv6OriginRendersWithBrackets() {
        let typed = HermesEndpoint(string: "http://[fd7a:115c:a1e0::1]:9119")!
        let location =
            "https://idp.example.com/authorize?redirect_uri=http%3A%2F%2F%5Bfd7a%3A115c%3Aa1e0%3A%3A2%5D%3A9119%2Fauth%2Fcallback"
        let diagnosis = BrowserAuthOrigin.diagnose(typed: typed, locationHeader: location, responseStatus: 302)
        #expect(
            diagnosis
                == .callbackOriginMismatch(
                    typedOrigin: "http://[fd7a:115c:a1e0::1]:9119",
                    callbackOrigin: "http://[fd7a:115c:a1e0::2]:9119",
                    suggestedStartingURL: "http://[fd7a:115c:a1e0::2]:9119"))
    }

    @Test func providerEncodingKeepsOneQueryValue() async throws {
        let provider = "a&b+c=d"
        let transport = RecordingAuthTransport(status: 302, location: nil)
        _ = try await BrowserAuthOrigin.preflight(
            typed: typedHost, provider: provider, native: false, transport: transport)
        let request = try #require(transport.requests.first)
        let components = URLComponents(url: request.url, resolvingAgainstBaseURL: false)
        let providers = components?.queryItems?.filter { $0.name == "provider" } ?? []
        #expect(providers.count == 1)
        #expect(providers.first?.value == provider)
    }

    @Test func callbackOriginMismatchErrorNamesStartingAddress() {
        let error = NativeSignInError.callbackOriginMismatch(startingURL: "http://hostinger-vps.tailfa5476.ts.net:9119")
        #expect(
            error.localizedDescription
                == "This server's browser sign-in must be started from http://hostinger-vps.tailfa5476.ts.net:9119. Enter that address and start browser sign-in again."
        )
    }
}
