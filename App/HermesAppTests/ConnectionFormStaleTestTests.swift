import Foundation
import HermesKit
import HermesUI
import XCTest

/// A thread-safe completion flag, so a bounded wait can end without a non-Sendable XCTest expectation.
private final class CompletionFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false

    func mark() { lock.withLock { finished = true } }
    var isFinished: Bool { lock.withLock { finished } }
}

/// Holds a connection test open so the form can be edited while it runs. A release is remembered, so a test may
/// release before the tester reaches the wait without losing the signal.
private actor TestGate {
    private(set) var didStart = false
    private(set) var didRelease = false
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func started() { didStart = true }

    func waitForRelease() async {
        guard !didRelease else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func release() {
        didRelease = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters.removeAll()
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

/// Passes at once.
private struct PassingTester: ConnectionTesting {
    func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        progress(.checkingServer)
        return ConnectionTestReport(serverVersion: "git.test")
    }
}

/// Asks for host-key trust and fails when it is not given.
private struct TrustTester: ConnectionTesting {
    let fingerprint: HostKeyFingerprint

    func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        guard await confirmHostKey(fingerprint) else { throw ConnectionTestFailure.hostKeyRejected }
        var report = ConnectionTestReport()
        report.acceptedHostKey = fingerprint
        return report
    }
}

/// A test that finishes after the form changed must not pass, pin a key or adapt the new address.
@MainActor
final class ConnectionFormStaleTestTests: XCTestCase {
    private func makeConnections(_ tester: any ConnectionTesting) -> ConnectionsModel {
        let services = ConnectionServices(
            credentials: InMemoryCredentialStore(), gatewayTester: tester, sshTester: tester,
            unlocker: AlwaysUnlocked(), offline: true)
        return ConnectionsModel(store: nil, services: services)
    }

    private func makeGatewayForm(
        _ tester: any ConnectionTesting = PassingTester()
    ) -> (ConnectionFormModel, ConnectionsModel) {
        let form = ConnectionFormModel(mode: .gateway)
        form.urlText = "http://box:9119"
        form.signInMethod = .none
        form.name = "Box"
        return (form, makeConnections(tester))
    }

    private func makeSSHForm(
        _ tester: any ConnectionTesting = PassingTester()
    ) -> (ConnectionFormModel, ConnectionsModel) {
        let form = ConnectionFormModel(mode: .ssh)
        form.host = "box"
        form.sshUser = "hermes"
        form.port = "22"
        return (form, makeConnections(tester))
    }

    private func pass(_ form: ConnectionFormModel, _ connections: ConnectionsModel) async {
        await form.runTest(with: connections)
        guard case .passed = form.test else {
            XCTFail("expected the test to pass, got \(form.test)")
            return
        }
    }

    /// Bounded wait for a main-actor condition, so a broken form cannot hang the suite.
    @discardableResult
    private func waitUntil(
        _ description: String, timeout: Duration = .seconds(5), condition: @MainActor () -> Bool
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for \(description)")
        return false
    }

    /// Bounded wait for a run to return, so a broken form cannot hang the suite.
    @discardableResult
    private func waitUntilFinished(_ flag: CompletionFlag, timeout: Duration = .seconds(5)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if flag.isFinished { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for the connection test to finish")
        return false
    }

    /// Bounded wait for the gated tester to start.
    private func waitForStart(_ gate: TestGate) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while clock.now < deadline {
            if await gate.didStart { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("timed out waiting for the connection test to start")
        return false
    }

    func testAnEditedAddressDiscardsTheCompletedTestAndItsAdaptedEndpoint() async throws {
        let gate = TestGate()
        var report = ConnectionTestReport(serverVersion: "git.test")
        report.adaptedEndpoint = HermesEndpoint(string: "http://100.64.150.77:9119")
        let (form, connections) = makeGatewayForm(GatedTester(gate: gate, report: report, failure: nil))

        let finished = CompletionFlag()
        let running = Task {
            await form.runTest(with: connections)
            finished.mark()
        }
        guard await waitForStart(gate) else {
            await gate.release()
            running.cancel()
            return
        }
        form.urlText = "http://other:9119"
        await gate.release()
        if await waitUntilFinished(finished) { await running.value } else { running.cancel() }

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
        let (form, connections) = makeGatewayForm(
            GatedTester(gate: gate, report: ConnectionTestReport(), failure: nil))
        form.signInMethod = .token
        form.token = "first"

        let finished = CompletionFlag()
        let running = Task {
            await form.runTest(with: connections)
            finished.mark()
        }
        guard await waitForStart(gate) else {
            await gate.release()
            running.cancel()
            return
        }
        form.token = "second"
        await gate.release()
        if await waitUntilFinished(finished) { await running.value } else { running.cancel() }

        XCTAssertEqual(form.test, .idle)
    }

    func testEarlyReleaseIsRememberedBeforeTheTesterWaits() async throws {
        let gate = TestGate()
        // Release before any tester can reach waitForRelease; the gate must remember it.
        await gate.release()
        let (form, connections) = makeGatewayForm(
            GatedTester(gate: gate, report: ConnectionTestReport(), failure: nil))

        let finished = CompletionFlag()
        let running = Task {
            await form.runTest(with: connections)
            finished.mark()
        }
        if await waitUntilFinished(finished) { await running.value } else { running.cancel() }

        if case .passed = form.test {} else { XCTFail("expected the early release to let the test pass") }
    }

    func testEveryGatewayTargetFieldClearsAPassedTest() async throws {
        let cases: [(String, (ConnectionFormModel) -> Void)] = [
            ("address", { $0.urlText = "http://other:9119" }),
            ("sign-in method", { $0.signInMethod = .password }),
            ("user name", { $0.username = "hermes" }),
            ("password", { $0.password = "pw" }),
            ("token", { $0.token = "token" }),
            ("browser provider", { $0.browserProvider = "basic" }),
        ]
        for (name, mutate) in cases {
            let (form, connections) = makeGatewayForm()
            await pass(form, connections)
            mutate(form)
            XCTAssertEqual(form.test, .idle, "editing the \(name) kept a passed test")
        }
    }

    func testEverySSHTargetFieldClearsAPassedTest() async throws {
        let cases: [(String, (ConnectionFormModel) -> Void)] = [
            ("host", { $0.host = "other" }),
            ("port", { $0.port = "2222" }),
            ("user name", { $0.sshUser = "other" }),
            ("key source", { $0.keySource = .importKey }),
            ("imported key", { $0.importText = "not a key" }),
            ("passphrase", { $0.passphrase = "phrase" }),
            ("Hermes path", { $0.hermesPath = "/opt/hermes" }),
            ("remote profile", { $0.remoteProfile = "ops" }),
            ("generated key", { $0.generateKey() }),
        ]
        for (name, mutate) in cases {
            let (form, connections) = makeSSHForm()
            await pass(form, connections)
            mutate(form)
            XCTAssertEqual(form.test, .idle, "editing the \(name) kept a passed test")
        }
    }

    func testEditingAFieldWhileTheHostKeySheetWaitsCancelsThePrompt() async throws {
        let fingerprint = HostKeyFingerprint(openSSHKey: "ssh-ed25519 AAAA test", fingerprint: "SHA256:test")
        let (form, connections) = makeSSHForm(TrustTester(fingerprint: fingerprint))

        let finished = CompletionFlag()
        let running = Task {
            await form.runTest(with: connections)
            finished.mark()
        }
        guard await waitUntil("the host-key prompt", condition: { form.pendingTrust != nil }) else {
            running.cancel()
            return
        }
        form.host = "other"
        _ = await waitUntil("the host-key prompt to close") { form.pendingTrust == nil }
        if await waitUntilFinished(finished) { await running.value } else { running.cancel() }

        XCTAssertEqual(form.test, .idle)
        XCTAssertNil(form.pendingTrust)
    }
}
