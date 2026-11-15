import Foundation
import HermesKit
import Testing

/// The port 9119 and HTTP fallbacks for a bare host or IP, and the sign-in offer for unknown providers.
@Suite struct AddressAlternativesTests {
    /// What the form does with `input`: parse it, then ask for the alternatives.
    private func urls(_ input: String) throws -> [String] {
        let parsed = try ConnectionAddress.parse(input).get()
        return AddressAlternatives.candidates(for: parsed.endpoint, typed: input).map(\.baseURL.absoluteString)
    }

    @Test func bareIPTriesTheDashboardPort() throws {
        #expect(try urls("192.168.1.20") == ["http://192.168.1.20:9119"])
        #expect(try urls("http://192.168.1.20") == ["http://192.168.1.20:9119"])
    }

    @Test func schemelessTailnetNameTriesHTTPOnTheDashboardPortThenDefault() throws {
        #expect(
            try urls("myhost.tailnet.ts.net") == ["http://myhost.tailnet.ts.net:9119", "http://myhost.tailnet.ts.net"])
    }

    @Test func aTypedPortIsTakenAsTyped() throws {
        #expect(try urls("192.168.1.20:8080").isEmpty)
        #expect(try urls("https://box.ts.net:8443").isEmpty)
    }

    @Test func publicHostsNeverGetPlainHTTP() throws {
        #expect(try urls("hermes.example.com") == ["https://hermes.example.com:9119"])
        #expect(try urls("https://hermes.example.com/hermes") == ["https://hermes.example.com:9119/hermes"])
    }

    @Test func aTypedHTTPSSchemeStaysHTTPS() throws {
        #expect(try urls("https://nas.local") == ["https://nas.local:9119"])
    }

    @Test func theNoteNamesTheAddressInUse() throws {
        let typed = try #require(HermesEndpoint(string: "http://192.168.1.20"))
        let adapted = try #require(HermesEndpoint(string: "http://192.168.1.20:9119"))
        #expect(HostFallback.note(typed: typed, adapted: adapted).contains("http://192.168.1.20:9119"))
    }

    private func probe(authRequired: Bool = false) -> ServerProbe {
        ServerProbe(authRequired: authRequired, authProviders: [])
    }

    @Test func probeFallsBackToThePortThatAnswers() async throws {
        let typed = try #require(HermesEndpoint(string: "http://192.168.1.20"))
        let log = Log()
        let found = try await AddressAlternatives.probe(typed, typed: "192.168.1.20") { endpoint in
            await log.add(endpoint.baseURL.absoluteString)
            guard endpoint.baseURL.port == 9119 else { throw ConnectionTestFailure.unreachable("refused") }
            return ServerProbe(authRequired: false, authProviders: [])
        }
        #expect(found.adaptedEndpoint?.baseURL.absoluteString == "http://192.168.1.20:9119")
        #expect(await log.urls == ["http://192.168.1.20", "http://192.168.1.20:9119"])
    }

    @Test func probeKeepsTheTypedAddressWhenItAnswers() async throws {
        let typed = try #require(HermesEndpoint(string: "http://192.168.1.20"))
        let found = try await AddressAlternatives.probe(typed, typed: "192.168.1.20") { _ in probe() }
        #expect(found.adaptedEndpoint == nil)
    }

    @Test func probeThrowsTheFirstFailureWhenNothingAnswers() async throws {
        let typed = try #require(HermesEndpoint(string: "http://192.168.1.20"))
        await #expect(throws: ConnectionTestFailure.unreachable("first")) {
            _ = try await AddressAlternatives.probe(typed, typed: "192.168.1.20") { endpoint in
                throw ConnectionTestFailure.unreachable(endpoint.baseURL.port == nil ? "first" : "later")
            }
        }
    }

    @Test func probeDoesNotSearchAfterAServerAnswersWithARefusal() async throws {
        let typed = try #require(HermesEndpoint(string: "http://192.168.1.20"))
        let log = Log()
        await #expect(throws: ConnectionTestFailure.rateLimited(retryAfter: nil)) {
            _ = try await AddressAlternatives.probe(typed, typed: "192.168.1.20") { endpoint in
                await log.add(endpoint.baseURL.absoluteString)
                throw ConnectionTestFailure.rateLimited(retryAfter: nil)
            }
        }
        #expect(await log.urls.count == 1)
    }

    @Test func unknownProviderTypesGoToTheBrowser() {
        let custom = AuthProviderInfo(name: "acme-sso")
        let options = SignInOptions(authRequired: true, providers: [custom], flows: ["cookie"])
        #expect(options.offer.browserProviders == [custom])
        #expect(options.offer.passwordProvider == nil && !options.offer.offersNothing)
        #expect(options.methods.contains(.browser))
    }

    @Test func severalProvidersAreAllOffered() {
        let basic = AuthProviderInfo(name: "basic", supportsPassword: true)
        let nous = AuthProviderInfo(name: "nous", displayName: "Nous Portal", supportsPassword: false)
        let custom = AuthProviderInfo(name: "acme-sso")
        let options = SignInOptions(authRequired: true, providers: [basic, nous, custom], flows: ["cookie"])
        #expect(options.offer.browserProviders.map(\.name) == ["nous", "acme-sso"])
        #expect(options.offer.passwordProvider == basic)
    }

    @Test func nativeSignInWithoutProvidersOffersOneGenericButton() {
        let options = SignInOptions(authRequired: true, providers: [], flows: ["native_pkce"])
        #expect(options.offer.genericBrowser && !options.offer.offersNothing)
    }

    @Test func authRequiredWithNoProvidersOffersNothing() {
        let options = SignInOptions(authRequired: true, providers: [], flows: ["cookie"])
        #expect(options.offer.offersNothing)
        #expect(options.methods == [.sessionToken], "A token still works")
    }

    @Test func aProbeWithoutFullOptionsKeepsUnknownProviders() {
        var probe = ServerProbe(authRequired: true, authProviders: ["basic", "acme-sso"])
        #expect(probe.signInKnown)
        #expect(probe.signInOptions.offer.passwordProvider?.name == "basic")
        #expect(probe.signInOptions.offer.browserProviders.map(\.name) == ["acme-sso"])
        probe = ServerProbe(authRequired: true, authProviders: [])
        #expect(!probe.signInKnown)
    }
}

/// Collects the addresses a probe saw.
private actor Log {
    private(set) var urls: [String] = []
    func add(_ url: String) { urls.append(url) }
}
