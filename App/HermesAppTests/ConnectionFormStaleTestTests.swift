import HermesKit
import HermesUI
import XCTest

/// Holds a connection test open so the form can be edited while it runs.
private actor TestGate {
    private var didStart = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func started() {
        didStart = true
        for waiter in startWaiters { waiter.resume() }
        startWaiters.removeAll()
    }

    func waitUntilStarted() async {
        guard !didStart else { return }
        await withCheckedContinuation { startWaiters.append($0) }
    }

    func waitForRelease() async {
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func release() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}

/// Answers every test after the gate opens.
private struct GatedTester: ConnectionTesting {
    let gate: TestGate
    let report: ConnectionTestReport
    let failure: ConnectionTestFailure?

    func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        progress(.reachingServer)
        await gate.started()
        await gate.waitForRelease()
        if let failure { throw failure }
        return report
    }
}

/// A test that finishes after the form changed must not pass, pin a key or adapt the new address.
@MainActor
final class ConnectionFormStaleTestTests: XCTestCase {
    private func makeForm(_ tester: GatedTester) -> (ConnectionFormModel, ConnectionsModel) {
        let services = ConnectionServices(
            credentials: InMemoryCredentialStore(), gatewayTester: tester, sshTester: tester,
            unlocker: AlwaysUnlocked(), offline: true)
        let connections = ConnectionsModel(store: nil, services: services)
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        form.signInMethod = .none
        form.name = "Box"
        return (form, connections)
    }

    func testAnEditedAddressDiscardsTheCompletedTestAndItsAdaptedEndpoint() async throws {
        let gate = TestGate()
        var report = ConnectionTestReport(serverVersion: "git.test")
        report.adaptedEndpoint = HermesEndpoint(string: "http://100.64.150.77:9119")
        let (form, connections) = makeForm(GatedTester(gate: gate, report: report, failure: nil))

        let running = Task { await form.runTest(with: connections) }
        await gate.waitUntilStarted()
        form.urlText = "http://other:9119"
        await gate.release()
        await running.value

        XCTAssertEqual(form.test, .idle)
        let connection = try form.makeConnection()
        guard case .gateway(let settings) = connection.kind else {
            return XCTFail("expected a gateway connection")
        }
        XCTAssertEqual(settings.endpoint.baseURL.absoluteString, "http://other:9119")
        XCTAssertNil(form.adaptedAddressNote)
    }

    func testAnEditedTokenDiscardsTheCompletedTest() async throws {
        let gate = TestGate()
        let (form, connections) = makeForm(GatedTester(gate: gate, report: ConnectionTestReport(), failure: nil))
        form.signInMethod = .token
        form.token = "first"

        let running = Task { await form.runTest(with: connections) }
        await gate.waitUntilStarted()
        form.token = "second"
        await gate.release()
        await running.value

        XCTAssertEqual(form.test, .idle)
    }
}
