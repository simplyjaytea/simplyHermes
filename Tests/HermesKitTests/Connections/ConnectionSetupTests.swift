import Foundation
import HermesKit
import Testing

@Suite struct ConnectionAddressTests {
    private func parsed(_ input: String) throws -> ConnectionAddress.Parsed {
        try ConnectionAddress.parse(input).get()
    }

    @Test func addsHTTPForLocalHostsAndHTTPSForPublicOnes() throws {
        #expect(try parsed("192.168.1.20:9119").endpoint.baseURL.absoluteString == "http://192.168.1.20:9119")
        #expect(try parsed("hermes.local:9119/").endpoint.baseURL.absoluteString == "http://hermes.local:9119")
        #expect(try parsed("100.64.150.77:9119").endpoint.baseURL.absoluteString == "http://100.64.150.77:9119")
        #expect(try parsed("hermes.example.com/ai").endpoint.baseURL.absoluteString == "https://hermes.example.com/ai")
        #expect(try parsed("  https://Hermes.example.com  ").warning == nil)
    }

    /// `tailscale serve` answers HTTPS on 443 and nothing on 80, so a bare MagicDNS name means HTTPS. With a port,
    /// the name points at Hermes itself, which speaks plain HTTP.
    @Test func bareMagicDNSNameMeansTailscaleServeHTTPS() throws {
        #expect(try parsed("box.tail1234.ts.net").endpoint.baseURL.absoluteString == "https://box.tail1234.ts.net")
        #expect(try parsed("Box.Tail1234.TS.net/").endpoint.baseURL.scheme == "https")
        #expect(
            try parsed("box.tail1234.ts.net/hermes").endpoint.baseURL.absoluteString
                == "https://box.tail1234.ts.net/hermes")
        #expect(try parsed("box.tail1234.ts.net").warning == nil)
        #expect(
            try parsed("box.tail1234.ts.net:9119").endpoint.baseURL.absoluteString == "http://box.tail1234.ts.net:9119")
        #expect(try parsed("box.tail1234.ts.net:9119").warning == .unencryptedTailscale)
        #expect(try parsed("http://box.tail1234.ts.net").endpoint.baseURL.scheme == "http")
    }

    @Test func plainHTTPRuleFollowsQ14() throws {
        #expect(try parsed("http://10.0.0.5:9119").warning == .unencryptedLocal)
        #expect(try parsed("http://172.20.1.1").warning == .unencryptedLocal)
        #expect(try parsed("http://100.101.102.103:9119").warning == .unencryptedTailscale)
        #expect(try parsed("http://[fd7a:115c:a1e0::1]:9119").warning == .unencryptedTailscale)
        #expect(try parsed("http://127.0.0.1:9119").warning == nil)
        #expect(try parsed("http://localhost:9119").warning == nil)
        #expect(
            ConnectionAddress.parse("http://hermes.example.com")
                == .failure(.httpNotAllowed(host: "hermes.example.com")))
        #expect(ConnectionAddress.parse("http://8.8.8.8") == .failure(.httpNotAllowed(host: "8.8.8.8")))
        #expect(ConnectionAddress.parse("http://172.32.0.1") == .failure(.httpNotAllowed(host: "172.32.0.1")))
    }

    @Test func rejectsBadInput() {
        #expect(ConnectionAddress.parse("   ") == .failure(.empty))
        #expect(ConnectionAddress.parse("ftp://box") == .failure(.unsupportedScheme("ftp")))
        #expect(ConnectionAddress.parse("user@box") == .failure(.invalid))
        #expect(ConnectionAddress.parse("https://") == .failure(.invalid))
    }

    @Test func localNetworkPermissionOnlyForPrivateHosts() throws {
        #expect(try parsed("192.168.0.2").needsLocalNetwork)
        #expect(try parsed("hermes.local").needsLocalNetwork)
        #expect(try !parsed("100.64.0.1").needsLocalNetwork)
        #expect(try !parsed("hermes.example.com").needsLocalNetwork)
    }

    @Test func classifiesHosts() {
        #expect(ConnectionAddress.classify(host: "[::1]") == .loopback)
        #expect(ConnectionAddress.classify(host: "fe80::1%en0") == .privateNetwork)
        #expect(ConnectionAddress.classify(host: "fd12::1") == .privateNetwork)
        #expect(ConnectionAddress.classify(host: "2001:db8::1") == .publicInternet)
        #expect(ConnectionAddress.classify(host: "nas") == .privateNetwork)
        #expect(ConnectionAddress.classify(host: "100.128.0.1") == .publicInternet)
        #expect(ConnectionAddress.classify(host: "169.254.3.4") == .privateNetwork)
    }
}

@Suite struct SavedConnectionsTests {
    private func gateway(_ url: String, name: String = "Home") -> ServerConnection {
        ServerConnection(name: name, kind: .gateway(GatewaySettings(endpoint: HermesEndpoint(string: url)!)))
    }

    private func ssh(_ host: String, profile: String? = nil) -> ServerConnection {
        ServerConnection(name: host, kind: .ssh(SSHSettings(host: host, username: "jt", remoteProfile: profile)))
    }

    @Test func faceIDDefaultsOnForSSHOnly() {
        #expect(ssh("box").requiresUnlock)
        #expect(!gateway("https://a.example").requiresUnlock)
    }

    @Test func dedupesGatewaysAndSSHHosts() {
        var saved = SavedConnections()
        saved.upsert(gateway("https://Hermes.example.com:443/"))
        saved.upsert(ssh("Box.lan"))
        #expect(saved.duplicate(of: gateway("https://hermes.example.com")) != nil)
        #expect(saved.duplicate(of: gateway("https://hermes.example.com/other")) == nil)
        #expect(saved.duplicate(of: ssh("box.lan")) != nil)
        #expect(saved.duplicate(of: ssh("box.lan", profile: "ops")) == nil)
        let first = saved.connections[0]
        #expect(saved.duplicate(of: first) == nil, "A connection is not its own duplicate")
    }

    @Test func firstConnectionBecomesActiveAndDeleteMovesIt() {
        var saved = SavedConnections()
        let one = gateway("https://one.example")
        let two = gateway("https://two.example")
        saved.upsert(one)
        saved.upsert(two)
        #expect(saved.active == one)
        saved.remove(id: one.id)
        #expect(saved.active == two)
        saved.remove(id: two.id)
        #expect(saved.activeID == nil)
    }

    @Test func storeRoundTripsWithoutSecrets() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: file)
        #expect(try store.load() == SavedConnections())
        var saved = SavedConnections()
        saved.upsert(
            ServerConnection(
                name: "Home",
                kind: .gateway(
                    GatewaySettings(
                        endpoint: HermesEndpoint(string: "http://192.168.1.2:9119")!,
                        signIn: .password(username: "jt"), remembersPassword: true))))
        saved.upsert(ssh("box"))
        try store.save(saved)
        #expect(try store.load() == saved)
    }
}

@Suite struct CredentialStoreTests {
    @Test func storesStringsAndKeysPerConnection() throws {
        let store = InMemoryCredentialStore()
        let one = UUID()
        let two = UUID()
        try store.setString("secret", for: .gatewayPassword, connection: one)
        try store.setSSHKey(.openSSH(text: "KEY", passphrase: nil), connection: one)
        try store.setString("token", for: .sessionToken, connection: two)
        #expect(try store.string(for: .gatewayPassword, connection: one) == "secret")
        #expect(try store.sshKey(connection: one) == .openSSH(text: "KEY", passphrase: nil))
        #expect(try store.string(for: .gatewayPassword, connection: two) == nil)
        try store.removeAll(connection: one)
        #expect(store.count == 1)
        try store.remove(.sshPassword, connection: two)
        #expect(try store.string(for: .sessionToken, connection: two) == "token")
    }
}

@Suite struct ConnectionQRCodeTests {
    @Test func parsesTheThreeForms() {
        #expect(
            ConnectionQRCode(scanned: "https://hermes.example.com/ai")
                == .gateway(url: "https://hermes.example.com/ai", name: nil, username: nil))
        #expect(
            ConnectionQRCode(scanned: "simplyhermes://add?url=http%3A%2F%2F192.168.1.2%3A9119&name=Home&user=jt")
                == .gateway(url: "http://192.168.1.2:9119", name: "Home", username: "jt"))
        #expect(ConnectionQRCode(scanned: "ssh://jt@box.lan:2222") == .ssh(host: "box.lan", port: 2222, username: "jt"))
        #expect(ConnectionQRCode(scanned: "ssh://box.lan") == nil)
        #expect(ConnectionQRCode(scanned: "hello") == nil)
        #expect(ConnectionQRCode(scanned: "simplyhermes://add?name=x") == nil)
    }
}

@Suite struct GatewayConnectionTesterTests {
    private let endpoint = HermesEndpoint(string: "http://192.168.1.2:9119/hermes")!

    private func connection(_ signIn: GatewaySignIn) -> ServerConnection {
        ServerConnection(name: "Home", kind: .gateway(GatewaySettings(endpoint: endpoint, signIn: signIn)))
    }

    private func run(
        _ http: FakeHTTP, _ signIn: GatewaySignIn, _ secrets: ConnectionSecrets = ConnectionSecrets()
    ) async throws -> ConnectionTestReport {
        let steps = StepLog()
        let report = try await GatewayConnectionTester(makeTransport: { http }, makeWebSocket: nil).test(
            connection(signIn), secrets: secrets, progress: { steps.append($0) }, confirmHostKey: { _ in false })
        #expect(steps.values.first == .reachingServer)
        return report
    }

    @Test func passwordSignInMintsATicket() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("health"))
        http.enqueue(200, try restFixture("status"))
        http.enqueue(200, #"{"ok":true}"#)
        http.enqueue(200, try restFixture("auth_me"))
        http.enqueue(200, #"{"ticket":"t-0123456789abcdef0123","ttl_seconds":30}"#)
        let report = try await run(http, .password(username: "tester"), ConnectionSecrets(password: "pw"))
        #expect(report.serverVersion == "git.d97007c")
        #expect(report.usesBasicAuth)
        #expect(report.signedInAs != nil)
        #expect(
            http.requests.map(\.url.path) == [
                "/hermes/api/health", "/hermes/api/status", "/hermes/auth/password-login", "/hermes/api/auth/me",
                "/hermes/api/auth/ws-ticket",
            ])
    }

    @Test func mapsFailures() async throws {
        let wrong = FakeHTTP()
        wrong.enqueue(200, try restFixture("health"))
        wrong.enqueue(200, try restFixture("status"))
        wrong.enqueue(401, #"{"detail":"bad"}"#)
        await #expect(throws: ConnectionTestFailure.wrongCredentials) {
            _ = try await run(wrong, .password(username: "tester"), ConnectionSecrets(password: "nope"))
        }

        let noLogin = FakeHTTP()
        noLogin.enqueue(200, try restFixture("health"))
        noLogin.enqueue(200, try restFixture("status"))
        await #expect(throws: ConnectionTestFailure.signInRequired(providers: ["basic"])) {
            _ = try await run(noLogin, .none)
        }

        let html = FakeHTTP()
        html.enqueue(200, "<html></html>", headers: ["Content-Type": "text/html"])
        await #expect(throws: ConnectionTestFailure.notHermes) { _ = try await run(html, .none) }

        let down = FakeHTTP()
        await #expect(throws: ConnectionTestFailure.unreachable("no scripted response")) {
            _ = try await run(down, .none)
        }

        await #expect(throws: ConnectionTestFailure.missingSecret) {
            _ = try await run(FakeHTTP(), .sessionToken)
        }
    }

    @Test func openServerNeedsNoSignIn() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"version":"0.20.0","auth_required":false}"#)
        http.enqueue(200, #"{"release_date":"2026.9.24","auth_required":false}"#)
        let report = try await run(http, .none)
        #expect(report.serverVersion == "0.20.0")
        #expect(report.releaseDate == "2026.9.24")
        #expect(report.signedInAs == nil)
        #expect(http.requests.count == 2)
    }
}

/// Live: the gateway test against the WP-03 testbed when `HERMES_TESTBED_URL` is set.
@Suite struct GatewayConnectionTesterLiveTests {
    @Test func testsTheTestbedGateway() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let tester = GatewayConnectionTester(makeWebSocket: { NIOWebSocketTransport() })
        let good = ServerConnection(
            name: "Testbed", kind: .gateway(GatewaySettings(endpoint: endpoint, signIn: .password(username: "tester"))))
        let report = try await tester.test(
            good, secrets: ConnectionSecrets(password: "testbed-password"), progress: { _ in },
            confirmHostKey: { _ in false })
        #expect(report.signedInAs != nil)
        #expect(report.usesBasicAuth)
        #expect(report.webSocketChecked, "WP-15: the WebSocket leg ran")
        #expect(report.compatibility == .compatible)

        await #expect(throws: ConnectionTestFailure.wrongCredentials) {
            _ = try await tester.test(
                good, secrets: ConnectionSecrets(password: "wrong"), progress: { _ in }, confirmHostKey: { _ in false })
        }
    }
}

final class StepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var steps: [ConnectionTestStep] = []
    func append(_ step: ConnectionTestStep) { lock.withLock { steps.append(step) } }
    var values: [ConnectionTestStep] { lock.withLock { steps } }
}
