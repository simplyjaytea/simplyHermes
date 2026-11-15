import Foundation
import HermesKit
import HermesUI
import XCTest

/// The one-press Connect flow and the provider-driven sign-in choices.
@MainActor
final class ConnectionFormConnectTests: XCTestCase {
    private struct PassingTester: ConnectionTesting {
        func test(
            _ connection: ServerConnection, secrets: ConnectionSecrets,
            progress: @escaping @Sendable (ConnectionTestStep) -> Void,
            confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
        ) async throws -> ConnectionTestReport {
            ConnectionTestReport(serverVersion: "git.test")
        }
    }

    private struct FailingTester: ConnectionTesting {
        func test(
            _ connection: ServerConnection, secrets: ConnectionSecrets,
            progress: @escaping @Sendable (ConnectionTestStep) -> Void,
            confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
        ) async throws -> ConnectionTestReport {
            throw ConnectionTestFailure.wrongCredentials
        }
    }

    private func makeConnections(
        _ tester: any ConnectionTesting, probe: (@Sendable (HermesEndpoint) async throws -> ServerProbe)? = nil
    ) -> ConnectionsModel {
        let services = ConnectionServices(
            credentials: InMemoryCredentialStore(), gatewayTester: tester, sshTester: tester,
            unlocker: AlwaysUnlocked(), probe: probe, offline: true)
        return ConnectionsModel(store: nil, services: services)
    }

    func testConnectTestsThenSaves() async throws {
        let connections = makeConnections(PassingTester())
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        form.signInMethod = .none
        let saved = try await form.connect(with: connections, localNetworkExplained: true)
        XCTAssertNotNil(saved)
        guard case .passed = form.test else { return XCTFail("the test should have passed, got \(form.test)") }
        XCTAssertEqual(connections.saved.connections.count, 1)
    }

    func testAFailedTestSavesNothingAndLeavesTheFormEditable() async throws {
        let connections = makeConnections(FailingTester())
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        form.signInMethod = .none
        let saved = try await form.connect(with: connections, localNetworkExplained: true)
        XCTAssertNil(saved)
        XCTAssertEqual(form.test, .failed(.wrongCredentials))
        XCTAssertTrue(connections.saved.connections.isEmpty)
    }

    func testConnectWaitsForAPasswordWhenTheServerNeedsOne() async throws {
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        form.signInMethod = .password
        form.username = "tester"
        XCTAssertEqual(form.connectMissing, "Enter the password.")
        form.password = "pw"
        XCTAssertNil(form.connectMissing)
    }

    func testTypingACredentialChoosesItsMethod() {
        let form = ConnectionFormModel(mode: .gateway)
        form.signInMethod = .browser
        form.token = "abc"
        XCTAssertEqual(form.signInMethod, .token)
        form.username = "u"
        XCTAssertEqual(form.signInMethod, .password)
    }

    func testAnUnknownProviderIsOfferedThroughTheBrowser() async {
        let options = SignInOptions(
            authRequired: true, providers: [AuthProviderInfo(name: "acme-sso")], flows: ["cookie"])
        let connections = makeConnections(
            PassingTester(),
            probe: { _ in ServerProbe(authRequired: true, authProviders: ["acme-sso"], signIn: options) })
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        await form.probeAddress(with: connections.services, localNetworkExplained: true)
        XCTAssertEqual(form.signInOffer?.browserProviders.map(\.name), ["acme-sso"])
        XCTAssertEqual(form.signInMethod, .browser)
    }

    func testAFailedProbeKeepsEveryMethodReachable() async {
        let connections = makeConnections(
            PassingTester(), probe: { _ in throw ConnectionTestFailure.unreachable("down") })
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        await form.probeAddress(with: connections.services, localNetworkExplained: true)
        XCTAssertNil(form.signInOffer)
        XCTAssertTrue(form.needsEveryMethod)
        XCTAssertEqual(Set(form.availableSignInMethods), Set(ConnectionFormModel.SignInMethod.allCases))
    }

    func testABareIPFallsBackToThePortHermesAnswersOn() async {
        let connections = makeConnections(
            PassingTester(),
            probe: { endpoint in
                guard endpoint.baseURL.port == 9119 else { throw ConnectionTestFailure.unreachable("refused") }
                return ServerProbe(authRequired: false, authProviders: [])
            })
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "192.168.1.20"
        await form.probeAddress(with: connections.services, localNetworkExplained: true)
        XCTAssertNotNil(form.adaptedAddressNote)
        XCTAssertEqual((try? form.makeConnection())?.address, "http://192.168.1.20:9119")
    }
}
