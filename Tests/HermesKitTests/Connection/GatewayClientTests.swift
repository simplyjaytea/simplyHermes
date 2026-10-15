import Foundation
import HermesKit
import Testing

private let endpoint = HermesEndpoint.testEndpoint

extension HermesEndpoint {
    fileprivate static var testEndpoint: HermesEndpoint { HermesEndpoint(string: "https://hermes.example")! }
}

private struct Rig {
    let client: GatewayClient
    let transport: FakeTransport
    let clock: ManualClock
    let log: EventLog
    let credentialRequests: CredentialLog

    init(
        provider: (@Sendable (GatewayCredentialRequest, Int) async throws -> GatewayCredential)? = nil,
        config: GatewayClientConfig? = nil
    ) async {
        transport = FakeTransport()
        clock = ManualClock()
        let log = CredentialLog()
        credentialRequests = log
        var cfg = config ?? GatewayClientConfig()
        cfg.reconnect = ReconnectPolicy(jitter: { $0 })
        client = GatewayClient(
            endpoint: endpoint, transport: transport,
            credentials: { request in
                let count = log.record(request)
                if let provider { return try await provider(request, count) }
                return .ticket("t\(count)")
            },
            clock: clock, config: cfg)
        self.log = EventLog(await client.events())
    }
}

private final class CredentialLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [GatewayCredentialRequest] = []
    func record(_ request: GatewayCredentialRequest) -> Int {
        lock.withLock {
            items.append(request)
            return items.count
        }
    }
    var all: [GatewayCredentialRequest] { lock.withLock { items } }
}

private func connected(_ rig: Rig, socket: FakeSocket) async throws {
    rig.transport.enqueue(.socket(socket))
    await rig.client.start()
    try await waitUntil("connected") { rig.log.states.contains(.connected) }
}

@Suite(.serialized) struct GatewayClientTests {
    @Test func handshakeSendsCapabilitiesAndConnects() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        let capabilities = socket.requests("client.capabilities")
        #expect(capabilities.count == 1)
        #expect(capabilities.first?.params?["server_requests"] as? Bool == true)
        #expect(rig.transport.connectURLs.first?.absoluteString.contains("ticket=t1") == true)
        await rig.client.stop()
    }

    @Test func callReturnsDecodedResultAndErrorThrows() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve { frame in
            guard let id = frame.id else { return [] }
            if frame.method == "ok" { return [Frames.result(id: id, #"{"value":7}"#)] }
            return [Frames.error(id: id, code: 4001, message: "nope")]
        }
        try await connected(rig, socket: socket)
        struct Out: Decodable, Sendable { var value: Int }
        let out: Out = try await rig.client.call("ok")
        #expect(out.value == 7)
        do {
            let _: Out = try await rig.client.call("bad")
            Issue.record("expected an RPC error")
        } catch let error as RPCError {
            #expect(error.code == 4001)
        }
        await rig.client.stop()
    }

    @Test func activeProfileScopesCallsThatTakeIt() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve { frame in
            guard let id = frame.id else { return [] }
            return [Frames.result(id: id, "{}")]
        }
        try await connected(rig, socket: socket)
        await rig.client.setProfile("ops")
        _ = try await rig.client.send(method: "session.list", params: .object(["limit": .int(5)]))
        _ = try await rig.client.send(method: "profiles.list")
        _ = try await rig.client.send(method: "gateway.ping")
        #expect(socket.requests("session.list").first?.params?["profile"] as? String == "ops")
        #expect(socket.requests("session.list").first?.params?["limit"] as? Int == 5)
        #expect(socket.requests("profiles.list").first?.params?["profile"] as? String == "ops")
        #expect(socket.requests("gateway.ping").first?.params == nil)
        await rig.client.setProfile(nil)
        _ = try await rig.client.send(method: "session.list")
        #expect(socket.requests("session.list").last?.params?["profile"] == nil)
        await rig.client.stop()
    }

    @Test func requestTimesOut() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        let task = Task { try await rig.client.send(method: "never", timeout: 10) }
        try await waitUntil("request sent") { !socket.requests("never").isEmpty }
        await rig.clock.advance(by: 11)
        do {
            _ = try await task.value
            Issue.record("expected a timeout")
        } catch let error as GatewayClientError {
            #expect(error == .timedOut(method: "never"))
        }
        await rig.client.stop()
    }

    @Test func requestBeforeConnectIsRejected() async throws {
        let rig = await Rig()
        await #expect(throws: GatewayClientError.notConnected) {
            _ = try await rig.client.send(method: "x")
        }
    }

    // MARK: Server requests

    @Test func serverRequestGetsHandlerResult() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        await rig.client.setServerRequestHandler(method: "approval") { _ in .object(["choice": .string("once")]) }
        try await connected(rig, socket: socket)
        socket.push(Frames.serverRequest(id: "srq-1", method: "approval"))
        try await waitUntil("response") { socket.sent.contains { $0.id == "srq-1" && $0.result != nil } }
        let reply = socket.sent.first { $0.id == "srq-1" }
        #expect(reply?.result?["choice"] as? String == "once")
        await rig.client.stop()
    }

    @Test func unregisteredServerRequestGetsMethodNotFound() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        socket.push(Frames.serverRequest(id: "srq-2", method: "tour"))
        try await waitUntil("error reply") { socket.sent.contains { $0.id == "srq-2" } }
        #expect(socket.sent.first { $0.id == "srq-2" }?.errorCode == -32601)
        await rig.client.stop()
    }

    @Test func throwingHandlerGetsInternalError() async throws {
        struct Boom: Error {}
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        await rig.client.setServerRequestHandler(method: "clarify") { _ in throw Boom() }
        try await connected(rig, socket: socket)
        socket.push(Frames.serverRequest(id: "srq-3", method: "clarify"))
        try await waitUntil("error reply") { socket.sent.contains { $0.id == "srq-3" } }
        #expect(socket.sent.first { $0.id == "srq-3" }?.errorCode == -32603)
        await rig.client.stop()
    }

    @Test func requestCancelStopsTheHandlerAndSendsNoReply() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        let started = Flag()
        await rig.client.setServerRequestHandler(method: "approval") { _ in
            started.set()
            try await Task.sleep(nanoseconds: 30_000_000_000)
            return .null
        }
        try await connected(rig, socket: socket)
        socket.push(Frames.serverRequest(id: "srq-4", method: "approval"))
        try await waitUntil("handler running") { started.value }
        socket.push(
            #"{"jsonrpc":"2.0","method":"event","params":{"type":"request.cancel","session_id":"s","payload":{"id":"srq-4"}}}"#
        )
        await settle()
        #expect(!socket.sent.contains { $0.id == "srq-4" })
        await rig.client.stop()
    }

    // MARK: Heartbeat and silence

    @Test func heartbeatPingsEveryFifteenSeconds() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        await rig.clock.advance(by: 15)
        try await waitUntil("first ping") { socket.requests("gateway.ping").count == 1 }
        socket.push(Frames.delta(session: "s", seq: 1))
        await rig.clock.advance(by: 15)
        try await waitUntil("second ping") { socket.requests("gateway.ping").count == 2 }
        await rig.client.stop()
    }

    @Test func noPingWhenServerDidNotAskForHeartbeat() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve(heartbeat: false)
        try await connected(rig, socket: socket)
        socket.push(Frames.delta(session: "s", seq: 1))
        await rig.clock.advance(by: 15)
        #expect(socket.requests("gateway.ping").isEmpty)
        await rig.client.stop()
    }

    @Test func fortyFiveSecondsOfSilenceDropsTheSocket() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        await rig.clock.advance(by: 46)
        try await waitUntil("socket dropped") { socket.isClosed }
        #expect(rig.log.states.contains { if case .waitingToReconnect = $0 { true } else { false } })
        await rig.client.stop()
    }

    @Test func missingReadyFailsTheAttempt() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        rig.transport.enqueue(.socket(socket))
        await rig.client.start()
        try await waitUntil("socket open") { !rig.transport.connectURLs.isEmpty }
        await rig.clock.advance(by: 16)
        try await waitUntil("socket closed") { socket.isClosed }
        await rig.client.stop()
    }

    // MARK: Reconnect and credentials

    @Test func backoffGrowsAndResetsAfterAStableSocket() async throws {
        let rig = await Rig()
        rig.transport.enqueue(.fail)
        rig.transport.enqueue(.fail)
        rig.transport.enqueue(.fail)
        let socket = FakeSocket()
        socket.serve()
        rig.transport.enqueue(.socket(socket))
        await rig.client.start()
        var delays: [Double] = []
        for round in 1...3 {
            try await waitUntil("wait \(round)") { rig.log.waits.count >= round }
            delays.append(rig.log.waits[round - 1])
            let wait = rig.log.waits[round - 1]
            await rig.clock.advance(by: wait, step: wait)
        }
        #expect(delays == [0.3, 0.6, 1.2])
        try await waitUntil("connected") { rig.log.states.contains(.connected) }
        await rig.client.stop()
    }

    @Test func socketDyingEarlyKeepsTheLadder() async throws {
        let rig = await Rig()
        let first = FakeSocket()
        first.serve()
        rig.transport.enqueue(.socket(first))
        await rig.client.start()
        try await waitUntil("connected") { rig.log.states.contains(.connected) }
        first.drop()
        try await waitUntil("waiting") { !rig.log.waits.isEmpty }
        #expect(rig.log.waitAttempts.first == 1)
        await rig.client.stop()
    }

    @Test func forbiddenUpgradeRetriesWithFreshTicketThenReauthenticates() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        rig.transport.enqueue(.reject(403))
        rig.transport.enqueue(.reject(403))
        rig.transport.enqueue(.socket(socket))
        await rig.client.start()
        try await waitUntil("connected") { rig.log.states.contains(.connected) }
        #expect(rig.credentialRequests.all == [.initial, .afterRejection, .reauthenticate])
        #expect(rig.transport.connectURLs.count == 3)
        await rig.client.stop()
    }

    @Test func thirdRejectionStopsWithAuthenticationRejected() async throws {
        let rig = await Rig()
        for _ in 0..<3 { rig.transport.enqueue(.reject(403)) }
        await rig.client.start()
        try await waitUntil("failed") { rig.log.states.contains(.failed(.authenticationRejected)) }
        #expect(rig.credentialRequests.all.count == 3)
    }

    @Test func signInRequiredFromProviderStopsTheClient() async throws {
        let rig = await Rig(provider: { _, _ in throw GatewaySignInRequired() })
        await rig.client.start()
        try await waitUntil("failed") { rig.log.states.contains(.failed(.signInRequired)) }
        #expect(rig.transport.connectURLs.isEmpty)
    }

    @Test func tokenCredentialUsesTokenQuery() async throws {
        let rig = await Rig(provider: { _, _ in .token("abc") })
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        #expect(rig.transport.connectURLs.first?.absoluteString.contains("token=abc") == true)
        await rig.client.stop()
    }

    @Test func connectTimeoutTriggersBackoff() async throws {
        let rig = await Rig()
        rig.transport.enqueue(.hang)
        await rig.client.start()
        try await waitUntil("connecting") { !rig.transport.connectURLs.isEmpty }
        await rig.clock.advance(by: 16)
        try await waitUntil("waiting") {
            rig.log.states.contains { if case .waitingToReconnect = $0 { true } else { false } }
        }
        await rig.client.stop()
    }

    @Test func stopFailsPendingRequests() async throws {
        let rig = await Rig()
        let socket = FakeSocket()
        socket.serve()
        try await connected(rig, socket: socket)
        let task = Task { try await rig.client.send(method: "slow") }
        try await waitUntil("sent") { !socket.requests("slow").isEmpty }
        await rig.client.stop()
        await #expect(throws: GatewayClientError.stopped) { _ = try await task.value }
        #expect(await rig.client.connectionState == .stopped)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    func set() { lock.withLock { flag = true } }
    var value: Bool { lock.withLock { flag } }
}
