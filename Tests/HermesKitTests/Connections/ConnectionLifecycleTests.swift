import Foundation
import HermesKit
import Testing

/// WP-15 gate: every transition of the connection state machine.
@Suite struct ConnectionLifecycleTests {
    private let summary = ServerSummary(serverVersion: "git.d97007c", releaseDate: "2026.9.24")

    /// A gateway machine brought to `connected`.
    private func connectedGateway() -> ConnectionLifecycle {
        var machine = ConnectionLifecycle(isSSH: false, requiresUnlock: false)
        _ = machine.handle(.connectRequested)
        _ = machine.handle(.serverChecked(summary))
        _ = machine.handle(.socket(.connected))
        return machine
    }

    @Test func gatewayHappyPath() {
        var machine = ConnectionLifecycle(isSSH: false, requiresUnlock: false)
        #expect(machine.phase == .idle)
        #expect(machine.handle(.connectRequested) == [.checkServer])
        #expect(machine.phase == .checkingServer)
        #expect(machine.handle(.serverChecked(summary)) == [.startSocket])
        #expect(machine.phase == .connecting)
        #expect(machine.handle(.socket(.connecting(attempt: 0))) == [])
        #expect(machine.phase == .connecting)
        #expect(machine.handle(.socket(.connected)) == [.recordConnected])
        #expect(machine.phase == .connected(summary))
        #expect(machine.handle(.connectRequested) == [], "Already connected")
    }

    @Test func sshWithFaceID() {
        var machine = ConnectionLifecycle(isSSH: true, requiresUnlock: true)
        #expect(machine.handle(.connectRequested) == [.unlock])
        #expect(machine.phase == .unlocking)
        #expect(machine.handle(.unlocked(true)) == [.openTunnel])
        #expect(machine.phase == .openingTunnel)
        #expect(machine.handle(.tunnelOpened) == [.checkServer])
        #expect(machine.handle(.serverChecked(summary)) == [.startSocket])
        #expect(machine.handle(.socket(.connected)) == [.recordConnected])
        #expect(machine.handle(.disconnectRequested) == [.stopSocket, .closeTunnel])
        #expect(machine.phase == .idle)
    }

    @Test func faceIDRefusedGoesBackToIdle() {
        var machine = ConnectionLifecycle(isSSH: true, requiresUnlock: true)
        _ = machine.handle(.connectRequested)
        #expect(machine.handle(.unlocked(false)) == [])
        #expect(machine.phase == .idle)
        #expect(machine.handle(.unlocked(true)) == [], "A late answer is ignored")
    }

    @Test func dropReconnectAndRecover() {
        var machine = connectedGateway()
        #expect(machine.handle(.socket(.waitingToReconnect(attempt: 0, delay: 1))) == [])
        #expect(machine.phase == .reconnecting(attempt: 1))
        #expect(machine.handle(.socket(.connecting(attempt: 1))) == [])
        #expect(machine.phase == .reconnecting(attempt: 1))
        #expect(machine.handle(.socket(.waitingToReconnect(attempt: 1, delay: 2))) == [])
        #expect(machine.phase == .reconnecting(attempt: 2))
        #expect(machine.handle(.socket(.connected)) == [], "Only the first connect is recorded")
        #expect(machine.phase == .connected(summary))
    }

    @Test func socketGivesUpNeedsSignIn() {
        var machine = connectedGateway()
        #expect(machine.handle(.socket(.failed(.signInRequired))) == [.stopSocket])
        #expect(machine.phase == .signInRequired)
        #expect(machine.handle(.connectRequested) == [.checkServer], "Signing in again starts over")
    }

    @Test func checkFailures() {
        var machine = ConnectionLifecycle(isSSH: true, requiresUnlock: false)
        _ = machine.handle(.connectRequested)
        #expect(machine.handle(.failed(.ssh("refused"))) == [.closeTunnel])
        #expect(machine.phase == .failed(.ssh("refused")))

        _ = machine.handle(.connectRequested)
        _ = machine.handle(.tunnelOpened)
        #expect(machine.handle(.failed(.wrongCredentials)) == [.closeTunnel])
        #expect(machine.phase == .signInRequired)

        var gateway = ConnectionLifecycle(isSSH: false, requiresUnlock: false)
        _ = gateway.handle(.connectRequested)
        #expect(gateway.handle(.failed(.unreachable("timeout"))) == [])
        #expect(gateway.phase == .failed(.unreachable("timeout")))
        #expect(gateway.handle(.failed(.notHermes)) == [], "Failures only count while busy")
        #expect(gateway.phase == .failed(.unreachable("timeout")))
    }

    @Test func tooOldServerNeedsAnUpdate() {
        var machine = ConnectionLifecycle(isSSH: true, requiresUnlock: false)
        _ = machine.handle(.connectRequested)
        _ = machine.handle(.tunnelOpened)
        let old = ServerSummary(releaseDate: "2026.8.1", compatibility: .updateRequired(found: "release 2026.8.1"))
        #expect(machine.handle(.serverChecked(old)) == [.closeTunnel])
        #expect(machine.phase == .updateRequired(found: "release 2026.8.1"))
    }

    @Test func desktopContractFromTheFirstSession() {
        var machine = connectedGateway()
        #expect(machine.handle(.contractReported(.int(8))) == [])
        #expect(machine.phase == .connected(summary))

        #expect(machine.handle(.contractReported(.int(9))) == [])
        var newer = summary
        newer.compatibility = .newerThanApp(contract: 9)
        #expect(machine.phase == .connected(newer))

        #expect(machine.handle(.contractReported(.int(7))) == [.stopSocket])
        #expect(machine.phase == .updateRequired(found: "desktop contract 7"))
    }

    @Test func eventsOutOfPhaseAreIgnored() {
        var machine = ConnectionLifecycle(isSSH: false, requiresUnlock: false)
        #expect(machine.handle(.tunnelOpened) == [])
        #expect(machine.handle(.serverChecked(summary)) == [])
        #expect(machine.handle(.socket(.connected)) == [])
        #expect(machine.handle(.contractReported(.int(1))) == [])
        #expect(machine.handle(.disconnectRequested) == [])
        #expect(machine.phase == .idle)
    }

    @Test func disconnectWhileChecking() {
        var machine = ConnectionLifecycle(isSSH: false, requiresUnlock: false)
        _ = machine.handle(.connectRequested)
        #expect(machine.handle(.disconnectRequested) == [])
        #expect(machine.phase == .idle)
        #expect(machine.handle(.serverChecked(summary)) == [], "A late result is ignored")
    }
}

/// The manager running the state machine with a fake driver and a fake WebSocket.
@Suite(.serialized) struct ConnectionManagerTests {
    private let connection = ServerConnection(
        name: "Home", kind: .gateway(GatewaySettings(endpoint: HermesEndpoint(string: "https://hermes.example")!)))

    @Test func connectsOnDemandAndSharesTheClient() async throws {
        let driver = FakeDriver()
        let socket = FakeSocket()
        socket.serve()
        driver.transport.enqueue(.socket(socket))
        let recorded = IDLog()
        let manager = ConnectionManager(driver: driver, onConnected: { recorded.append($0) })
        #expect(await manager.phase(of: connection.id) == .idle)

        async let first = manager.client(for: connection)
        async let second = manager.client(for: connection)
        let (one, two) = try await (first, second)
        #expect(one === two)
        #expect(driver.checks == 1)
        #expect(recorded.values == [connection.id])
        guard case .connected(let summary) = await manager.phase(of: connection.id) else {
            Issue.record("not connected")
            return
        }
        #expect(summary.serverVersion == "git.d97007c")
        #expect(try await manager.client(for: connection) === one, "Connected: no new check")
        #expect(driver.checks == 1)
        #expect(await manager.rest(for: connection.id) != nil)

        await manager.disconnect(connection.id)
        #expect(await manager.phase(of: connection.id) == .idle)
        #expect(await manager.rest(for: connection.id) == nil)
    }

    @Test func failuresReachTheCaller() async throws {
        let driver = FakeDriver()
        driver.checkResult = .failure(ConnectionTestFailure.wrongCredentials)
        let manager = ConnectionManager(driver: driver)
        await #expect(throws: ConnectionUnavailable(phase: .signInRequired)) {
            _ = try await manager.client(for: connection)
        }

        let old = FakeDriver()
        old.checkResult = .success(ServerSummary(compatibility: .updateRequired(found: "release 2026.1.1")))
        let oldManager = ConnectionManager(driver: old)
        await #expect(throws: ConnectionUnavailable(phase: .updateRequired(found: "release 2026.1.1"))) {
            _ = try await oldManager.client(for: connection)
        }
        #expect(old.transport.connectURLs.isEmpty, "No WebSocket for a server that is too old")
    }

    @Test func faceIDRefusedThrowsIdle() async throws {
        let driver = FakeDriver()
        driver.unlockAnswer = false
        let locked = ServerConnection(name: "Box", kind: connection.kind, requiresUnlock: true)
        let manager = ConnectionManager(driver: driver)
        await #expect(throws: ConnectionUnavailable(phase: .idle)) { _ = try await manager.client(for: locked) }
        #expect(driver.checks == 0)
    }

    @Test func sshClosesTheTunnelOnFailureAndDisconnect() async throws {
        let driver = FakeDriver()
        driver.checkResult = .failure(ConnectionTestFailure.notHermes)
        let box = ServerConnection(
            name: "Box", kind: .ssh(SSHSettings(host: "box", username: "jt")), requiresUnlock: false)
        let manager = ConnectionManager(driver: driver)
        await #expect(throws: ConnectionUnavailable(phase: .failed(.notHermes))) {
            _ = try await manager.client(for: box)
        }
        try await waitUntil("tunnel closed") { driver.closedTunnels == 1 }

        driver.checkResult = .success(ServerSummary())
        let socket = FakeSocket()
        socket.serve()
        driver.transport.enqueue(.socket(socket))
        _ = try await manager.client(for: box)
        #expect(driver.openedTunnels == 2)
        await manager.disconnect(box.id)
        try await waitUntil("second tunnel closed") { driver.closedTunnels == 2 }
    }

    @Test func phaseChangesAreStreamed() async throws {
        let driver = FakeDriver()
        let socket = FakeSocket()
        socket.serve()
        driver.transport.enqueue(.socket(socket))
        let manager = ConnectionManager(driver: driver)
        let changes = await manager.phaseChanges()
        _ = try await manager.client(for: connection)
        var seen: [ConnectionPhase] = []
        for await change in changes {
            seen.append(change.phase)
            if case .connected = change.phase { break }
        }
        #expect(seen.first == .checkingServer)
        #expect(seen.contains(.connecting))
    }
}

/// A scripted ``ConnectionDriver``.
private final class FakeDriver: ConnectionDriver, @unchecked Sendable {
    private let lock = NSLock()
    let transport = FakeTransport()
    var unlockAnswer = true
    var checkResult: Result<ServerSummary, any Error> = .success(ServerSummary(serverVersion: "git.d97007c"))
    private var counts = (checks: 0, opened: 0, closed: 0)

    var checks: Int { lock.withLock { counts.checks } }
    var openedTunnels: Int { lock.withLock { counts.opened } }
    var closedTunnels: Int { lock.withLock { counts.closed } }

    func unlock(_ connection: ServerConnection) async -> Bool { unlockAnswer }

    func openTunnel(_ connection: ServerConnection) async throws -> OpenedTunnel {
        lock.withLock { counts.opened += 1 }
        return OpenedTunnel(endpoint: HermesEndpoint(string: "http://127.0.0.1:50000")!, sessionToken: "tok") {
            self.lock.withLock { self.counts.closed += 1 }
        }
    }

    func checkServer(_ connection: ServerConnection, tunnel: OpenedTunnel?) async throws -> CheckedServer {
        lock.withLock { counts.checks += 1 }
        let summary = try lock.withLock { checkResult }.get()
        let endpoint = tunnel?.endpoint ?? HermesEndpoint(string: "https://hermes.example")!
        return CheckedServer(
            summary: summary, endpoint: endpoint, rest: RESTClient(endpoint: endpoint, transport: FakeHTTP()),
            credentials: { _ in .ticket("t") })
    }

    func webSocketTransport(for connection: ServerConnection) -> any WebSocketTransport { transport }
}

private final class IDLog: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [UUID] = []
    func append(_ id: UUID) { lock.withLock { ids.append(id) } }
    var values: [UUID] { lock.withLock { ids } }
}

/// Live: the manager against the WP-03 testbed when `HERMES_TESTBED_URL` is set. A remembered password signs in
/// silently, the socket connects on demand, and a session result passes the desktop contract check.
@Suite struct ConnectionManagerLiveTests {
    @Test func connectsToTheTestbedOnDemand() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let store = InMemoryCredentialStore()
        let connection = ServerConnection(
            name: "Testbed",
            kind: .gateway(
                GatewaySettings(endpoint: endpoint, signIn: .password(username: "tester"), remembersPassword: true)))
        try store.setString("testbed-password", for: .gatewayPassword, connection: connection.id)
        let manager = ConnectionManager(driver: LiveGatewayDriver(credentials: store))
        let client = try await liveTimeout(seconds: 30) { try await manager.client(for: connection) }
        guard case .connected(let summary) = await manager.phase(of: connection.id) else {
            Issue.record("not connected")
            return
        }
        #expect(summary.signedInAs != nil)
        #expect(summary.compatibility == .compatible)
        let created: SessionCreateResult = try await client.call("session.create", params: SessionCreateParams())
        await manager.reportSessionInfo(created.info, for: connection.id)
        #expect(await manager.phase(of: connection.id) == .connected(summary), "Contract 8 is what the app speaks")
        await manager.disconnect(connection.id)
    }
}

/// Gateways only, with the NIO WebSocket (Linux has no URLSession WebSockets).
private struct LiveGatewayDriver: ConnectionDriver {
    let credentials: any CredentialStore

    func unlock(_ connection: ServerConnection) async -> Bool { true }
    func openTunnel(_ connection: ServerConnection) async throws -> OpenedTunnel {
        throw ConnectionTestFailure.ssh("gateway only")
    }
    func checkServer(_ connection: ServerConnection, tunnel: OpenedTunnel?) async throws -> CheckedServer {
        guard case .gateway(let settings) = connection.kind else { throw ConnectionTestFailure.notHermes }
        let session = GatewayAuthSession(connectionID: connection.id, settings: settings, credentials: credentials)
        return try await CheckedServer.gateway(session, endpoint: settings.endpoint)
    }
    func webSocketTransport(for connection: ServerConnection) -> any WebSocketTransport { NIOWebSocketTransport() }
}
