import Foundation
import HermesKit
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket
import Testing

@testable import HermesSSH

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// WP-14 CI gate against the WP-03 testbed `sshd`: start the dashboard over SSH, open `/api/ws` through the
/// forwarder and run one chat turn. Runs only when `HERMES_SSH_TEST_KEY` points at the testbed key
/// (CI's `ssh-integration` job sets it after `testbed/scripts/up.sh`).
@Suite(.enabled(if: SSHTestbed.keyPath != nil), .serialized, .timeLimit(.minutes(5)))
struct SSHTunnelIntegrationTests {
    // Quarantined again (board row quarantine-ssh-tunnel-chat-turn, until 2026-11-19). #117 re-enabled it, and #123's
    // Testbed run 43198484235 hung in round 1 at step ws.gateway.ready: the WebSocket opened through the tunnel, but
    // the gateway's ready frame never came, so the round ran to the 5-minute limit and the job to its 20-minute
    // timeout.
    // Rounds 2-4 passed. The step logger only warns after 30 s; it does not fail the step.
    // Eight rounds per run, each under the suite's own time limit, so a rare hang shows up in fewer CI runs.
    @Test(
        .disabled("Quarantined: ws.gateway.ready sometimes never arrives in CI (row quarantine-ssh-tunnel-chat-turn)"),
        arguments: 1...8)
    func chatTurnThroughTunnel(round: Int) async throws {
        SSHTestbed.log("ssh-tunnel round \(round) of 8")
        let configuration = try SSHTestbed.configuration(hostKey: .trustOnFirstUse { _ in true })
        let tunnel = SSHTunnel(configuration: configuration)
        let endpoint = try await SSHTestbed.step("tunnel.start", warnAfter: 60) { try await tunnel.start() }
        #expect(endpoint.hostKey.fingerprint.hasPrefix("SHA256:"))
        #expect(endpoint.sessionToken.count == 64)

        do {
            // REST: token required on the loopback bind.
            let status = try await SSHTestbed.step("rest.unauthorized", warnAfter: 20) {
                try await SSHTestbed.get(endpoint.baseURL.appending(path: "api/sessions"), headers: [:])
            }
            #expect(status == 401)
            let authorized = try await SSHTestbed.step("rest.authorized", warnAfter: 20) {
                let url = endpoint.baseURL.appending(path: "api/sessions")
                return try await SSHTestbed.get(url, headers: endpoint.restHeaders)
            }
            #expect(authorized == 200)

            // WebSocket chat turn. Each RPC inside it logs its own step.
            let turn = try await SSHTestbed.chatTurn(url: endpoint.webSocketURL())
            #expect(turn.submitStatus == "streaming")
            #expect(turn.text?.isEmpty == false)

        } catch {
            await SSHTestbed.step("tunnel.stop (after error)", warnAfter: 30) { await tunnel.stop() }
            throw error
        }
        await SSHTestbed.step("tunnel.stop", warnAfter: 30) { await tunnel.stop() }
        #expect(await tunnel.currentEndpoint == nil)
        let afterStop = try? await SSHTestbed.get(endpoint.baseURL.appending(path: "api/status"), headers: [:])
        #expect(afterStop == nil)
    }

    /// WP-22: the connection form's Test button for SSH, with first-connect trust, then pinned.
    @Test func connectionTestTrustsThenPins() async throws {
        let keyText = try String(contentsOfFile: try #require(SSHTestbed.keyPath), encoding: .utf8)
        let environment = SSHTestbed.environment
        var settings = SSHSettings(
            host: environment["HERMES_SSH_TEST_HOST"] ?? "127.0.0.1",
            port: Int(environment["HERMES_SSH_TEST_PORT"] ?? "") ?? 2222,
            username: environment["HERMES_SSH_TEST_USER"] ?? "tester", authentication: .importedKey)
        let secrets = ConnectionSecrets(sshKey: try SSHKeyMaterial.importKey(keyText, passphrase: nil))
        let connection = { ServerConnection(name: "Testbed", kind: .ssh(settings)) }

        let report = try await SSHConnectionTester().test(
            connection(), secrets: secrets, progress: { _ in }, confirmHostKey: { _ in true })
        let hostKey = try #require(report.acceptedHostKey)
        #expect(hostKey.fingerprint.hasPrefix("SHA256:"))
        #expect(report.serverVersion?.isEmpty == false)

        settings.pinnedHostKey = hostKey.openSSHKey
        let pinned = try await SSHConnectionTester().test(
            connection(), secrets: secrets, progress: { _ in },
            confirmHostKey: { _ in
                Issue.record("a pinned key must not ask")
                return false
            })
        #expect(pinned.acceptedHostKey == hostKey)

        settings.pinnedHostKey = nil
        await #expect(throws: ConnectionTestFailure.hostKeyRejected) {
            _ = try await SSHConnectionTester().test(
                connection(), secrets: secrets, progress: { _ in }, confirmHostKey: { _ in false })
        }
    }

    @Test func pinnedHostKeyMismatchFailsHard() async throws {
        let wrongKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"
        let tunnel = SSHTunnel(configuration: try SSHTestbed.configuration(hostKey: .pinned(openSSHKey: wrongKey)))
        await #expect {
            _ = try await tunnel.start()
        } throws: { error in
            if case SSHTunnelError.hostKeyMismatch(let expected, _) = error {
                return expected == "SHA256:+DiY3wvvV6TuJJhbpZisF/zLDA0zPMSvHdkr4UvCOqU"
            }
            return false
        }
    }

    @Test func pinnedHostKeyAcceptedOnReconnect() async throws {
        let first = SSHTunnel(configuration: try SSHTestbed.configuration(hostKey: .trustOnFirstUse { _ in true }))
        let hostKey = try await first.start().hostKey
        await first.stop()
        let second = SSHTunnel(
            configuration: try SSHTestbed.configuration(hostKey: .pinned(openSSHKey: hostKey.openSSHKey)))
        #expect(try await second.start().hostKey == hostKey)
        await second.stop()
    }

    @Test func missingCustomHermesPathIsReported() async throws {
        var configuration = try SSHTestbed.configuration(hostKey: .trustOnFirstUse { _ in true })
        configuration.hermesPath = "/nonexistent/hermes"
        let tunnel = SSHTunnel(configuration: configuration)
        await #expect(throws: SSHTunnelError.hermesNotFound) { _ = try await tunnel.start() }
    }
}

enum SSHTestbed {
    static let environment = ProcessInfo.processInfo.environment
    static var keyPath: String? { environment["HERMES_SSH_TEST_KEY"] }

    static func configuration(hostKey: HostKeyPolicy) throws -> SSHConfiguration {
        let keyText = try String(contentsOfFile: try #require(keyPath), encoding: .utf8)
        return SSHConfiguration(
            host: environment["HERMES_SSH_TEST_HOST"] ?? "127.0.0.1",
            port: Int(environment["HERMES_SSH_TEST_PORT"] ?? "") ?? 2222,
            username: environment["HERMES_SSH_TEST_USER"] ?? "tester",
            credential: try SSHKeys.importOpenSSHPrivateKey(keyText),
            hostKey: hostKey,
            ownershipID: RemoteDashboard.makeOwnershipID()
        )
    }

    /// Runs one step of the tunnel test and logs it to stderr: when it starts, when it ends, and a warning once it has run
    /// longer than `warnAfter` seconds. The step is not cancelled, so a hang still ends at the suite's time limit, but the
    /// log names the step that never finished.
    static func step<T>(_ name: String, warnAfter seconds: Int, _ body: () async throws -> T) async rethrows -> T {
        log("ssh-tunnel step \(name): started")
        let clock = ContinuousClock()
        let start = clock.now
        let watchdog = Task {
            try await Task.sleep(for: .seconds(seconds))
            log("ssh-tunnel step \(name): STILL RUNNING after \(seconds) s")
        }
        defer { watchdog.cancel() }
        do {
            let value = try await body()
            log("ssh-tunnel step \(name): done in \(start.duration(to: clock.now))")
            return value
        } catch {
            log("ssh-tunnel step \(name): failed after \(start.duration(to: clock.now)): \(error)")
            throw error
        }
    }

    static func log(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }

    static func get(_ url: URL, headers: [String: String]) async throws -> Int {
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (_, response) = try await URLSession.shared.data(for: request)
        return (response as? HTTPURLResponse)?.statusCode ?? 0
    }

    enum Upgrade {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case notUpgraded
    }

    /// One chat turn over `/api/ws`: just enough JSON-RPC for the gate (the real client is WP-11).
    static func chatTurn(url: URL) async throws -> (submitStatus: String?, text: String?) {
        let socket = try await step("ws.connect", warnAfter: 30) { try await connectWebSocket(url: url) }
        return try await socket.executeThenClose { inbound, outbound in
            let rpc = JSONRPC(inbound: inbound.makeAsyncIterator(), outbound: outbound)
            _ = try await step("ws.gateway.ready", warnAfter: 30) { try await rpc.event("gateway.ready") }
            _ = try await step("ws.client.capabilities", warnAfter: 30) {
                try await rpc.call("client.capabilities", ["server_requests": true])
            }
            let session = try await step("ws.session.create", warnAfter: 30) {
                try await rpc.call("session.create", [:])
            }
            let sessionID = try #require(session["session_id"] as? String)
            let submit = try await step("ws.prompt.submit", warnAfter: 30) {
                try await rpc.call("prompt.submit", ["session_id": sessionID, "text": "hello [[scenario:text]]"])
            }
            let complete = try await step("ws.message.complete", warnAfter: 60) {
                try await rpc.event("message.complete")
            }
            return (submit["status"] as? String, complete["text"] as? String)
        }
    }

    /// Uses NIO because `URLSessionWebSocketTask` needs a libcurl with WebSocket support, which Linux images lack.
    static func connectWebSocket(url: URL) async throws -> NIOAsyncChannel<WebSocketFrame, WebSocketFrame> {
        let host = try #require(url.host())
        let port = try #require(url.port)
        let uri = url.path() + "?" + (url.query() ?? "")
        let upgrade: EventLoopFuture<Upgrade> = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .connect(host: host, port: port) { channel in
                channel.eventLoop.makeCompletedFuture {
                    let upgrader = NIOTypedWebSocketClientUpgrader<Upgrade>(maxFrameSize: 1 << 24) { channel, _ in
                        channel.eventLoop.makeCompletedFuture {
                            .websocket(try NIOAsyncChannel(wrappingChannelSynchronously: channel))
                        }
                    }
                    var headers = HTTPHeaders()
                    headers.add(name: "Host", value: "\(host):\(port)")
                    let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)
                    let configuration = NIOTypedHTTPClientUpgradeConfiguration<Upgrade>(
                        upgradeRequestHead: head, upgraders: [upgrader],
                        notUpgradingCompletionHandler: { $0.eventLoop.makeSucceededFuture(.notUpgraded) })
                    return try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
                        configuration: .init(upgradeConfiguration: configuration))
                }
            }
        guard case .websocket(let socket) = try await upgrade.get() else { throw TestbedError.rpc("upgrade refused") }
        return socket
    }

    final class JSONRPC {
        private var frames: NIOAsyncChannelInboundStream<WebSocketFrame>.AsyncIterator
        private let outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>
        private var nextID = 0

        init(
            inbound: NIOAsyncChannelInboundStream<WebSocketFrame>.AsyncIterator,
            outbound: NIOAsyncChannelOutboundWriter<WebSocketFrame>
        ) {
            self.frames = inbound
            self.outbound = outbound
        }

        func call(_ method: String, _ params: [String: Any]) async throws -> [String: Any] {
            nextID += 1
            let id = "t\(nextID)"
            let frame: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
            let data = try JSONSerialization.data(withJSONObject: frame)
            try await outbound.write(
                WebSocketFrame(fin: true, opcode: .text, maskKey: .random(), data: ByteBuffer(bytes: data)))
            while true {
                let message = try await receive()
                if message["id"] as? String == id {
                    if let error = message["error"] { throw TestbedError.rpc("\(method): \(error)") }
                    return message["result"] as? [String: Any] ?? [:]
                }
            }
        }

        func event(_ type: String) async throws -> [String: Any] {
            while true {
                let message = try await receive()
                if let params = message["params"] as? [String: Any], params["type"] as? String == type {
                    return params["payload"] as? [String: Any] ?? [:]
                }
            }
        }

        private func receive() async throws -> [String: Any] {
            while let frame = try await frames.next() {
                switch frame.opcode {
                case .text:
                    let object = try JSONSerialization.jsonObject(with: Data(String(buffer: frame.data).utf8))
                    return object as? [String: Any] ?? [:]
                case .ping:
                    try await outbound.write(
                        WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.data))
                case .connectionClose:
                    throw TestbedError.rpc("socket closed")
                default:
                    continue
                }
            }
            throw TestbedError.rpc("socket ended")
        }
    }

    enum TestbedError: Error {
        case rpc(String)
    }
}
