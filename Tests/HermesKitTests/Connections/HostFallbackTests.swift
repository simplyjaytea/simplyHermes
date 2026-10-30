import Foundation
import HermesKit
import Testing

/// A resolver with fixed answers.
struct FixedResolver: HostResolving {
    var answers: [String: [String]]
    func addresses(of host: String) async -> [String] { answers[host] ?? [] }
}

/// The body Hermes sends for a Host it doesn't know. Seen live on a server bound to its Tailscale IP.
let invalidHostBody =
    #"{"detail":"Invalid Host header. Dashboard requests must use the bound hostname or the configured public hostname."}"#

@Suite struct HostFallbackTests {
    private let resolver = FixedResolver(answers: [
        "box": ["100.64.150.77"], "box.tail1234.ts.net": ["100.64.150.77", "fd7a:115c:a1e0::1%utun4"],
    ])

    @Test func swapsTheNameForEachAddressAndKeepsPortAndPath() async throws {
        let endpoint = try #require(HermesEndpoint(string: "http://box.tail1234.ts.net:9119/hermes"))
        let found = await HostFallback.candidates(for: endpoint, resolver: resolver)
        #expect(
            found.map(\.baseURL.absoluteString) == [
                "http://100.64.150.77:9119/hermes", "http://[fd7a:115c:a1e0::1]:9119/hermes",
            ])
    }

    @Test func hasNoFallbackForHTTPSOrAnAddress() async throws {
        let https = try #require(HermesEndpoint(string: "https://box.tail1234.ts.net"))
        #expect(await HostFallback.candidates(for: https, resolver: resolver).isEmpty)
        let address = try #require(HermesEndpoint(string: "http://100.64.150.77:9119"))
        #expect(await HostFallback.candidates(for: address, resolver: resolver).isEmpty)
        let unknown = try #require(HermesEndpoint(string: "http://nowhere:9119"))
        #expect(await HostFallback.candidates(for: unknown, resolver: resolver).isEmpty)
    }

    @Test func noteNamesTheTypedNameAndTheAddress() throws {
        let typed = try #require(HermesEndpoint(string: "http://box:9119"))
        let adapted = try #require(HermesEndpoint(string: "http://100.64.150.77:9119"))
        #expect(
            HostFallback.note(typed: typed, adapted: adapted)
                == "Hermes doesn't answer to box, so the app connects to 100.64.150.77, the same server.")
    }

    @Test func systemResolverFindsLocalhost() async {
        #expect(await SystemHostResolver().addresses(of: "localhost").contains("127.0.0.1"))
    }
}

@Suite struct GatewayHostFallbackTests {
    private let resolver = FixedResolver(answers: ["box": ["100.64.150.77"]])

    private func connection(_ url: String) -> ServerConnection {
        ServerConnection(
            name: "Box",
            kind: .gateway(
                GatewaySettings(endpoint: HermesEndpoint(string: url)!, signIn: .password(username: "hermes"))))
    }

    /// Hermes bound to its Tailscale IP refuses `box` and answers on the IP. The test signs in there and reports the
    /// IP endpoint to save.
    @Test func aRefusedNameSignsInOnTheAddress() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(200, try restFixture("health"))
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, try restFixture("auth_me"))
        http.enqueue(200, #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
        let tester = GatewayConnectionTester(makeTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let report = try await tester.test(
            connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
            confirmHostKey: { _ in false })
        #expect(report.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.77:9119")
        #expect(report.signedInAs != nil)
        #expect(
            http.requests.map { "\($0.url.host ?? "") \($0.url.path)" } == [
                "box /api/health", "100.64.150.77 /api/health", "100.64.150.77 /api/status",
                "100.64.150.77 /auth/password-login", "100.64.150.77 /api/auth/me", "100.64.150.77 /api/auth/ws-ticket",
            ])
    }

    @Test func aNameThatWorksIsKept() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("health"))
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, try restFixture("auth_me"))
        http.enqueue(200, #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
        let tester = GatewayConnectionTester(makeTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let report = try await tester.test(
            connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
            confirmHostKey: { _ in false })
        #expect(report.adaptedEndpoint == nil)
    }

    @Test func withoutAWorkingAddressTheRefusalStands() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(400, invalidHostBody)
        let tester = GatewayConnectionTester(makeTransport: { http }, makeWebSocket: nil, resolver: resolver)
        do {
            _ = try await tester.test(
                connection("http://box:9119"), secrets: ConnectionSecrets(password: "pw"), progress: { _ in },
                confirmHostKey: { _ in false })
            Issue.record("the test should fail")
        } catch let failure as ConnectionTestFailure {
            #expect(failure.isHostRejected)
        }
    }

    @Test func probeReportsTheAddress() async throws {
        let http = FakeHTTP()
        http.enqueue(400, invalidHostBody)
        http.enqueue(200, try restFixture("health"))
        http.enqueue(
            200, #"{"providers":[{"name":"basic","display_name":"Username & Password","supports_password":true}]}"#)
        let tester = GatewayConnectionTester(makeTransport: { http }, makeWebSocket: nil, resolver: resolver)
        let probe = try #require(await tester.probe(HermesEndpoint(string: "http://box:9119")!))
        #expect(probe.adaptedEndpoint?.baseURL.absoluteString == "http://100.64.150.77:9119")
    }
}

/// Runs against a real Hermes when `HERMES_HOST_FALLBACK_URL` names an address it refuses, such as the MagicDNS short
/// name of a server bound to its Tailscale IP.
@Suite struct GatewayHostFallbackLiveTests {
    @Test func probeAdaptsOnARealServer() async throws {
        guard let text = ProcessInfo.processInfo.environment["HERMES_HOST_FALLBACK_URL"],
            let endpoint = HermesEndpoint(string: text)
        else { return }
        let probe = try #require(await GatewayConnectionTester(makeWebSocket: nil).probe(endpoint))
        #expect(probe.adaptedEndpoint != nil)
        #expect(probe.authRequired)
    }
}
