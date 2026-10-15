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
    @Test func chatTurnThroughTunnel() async throws {
        let configuration = try SSHTestbed.configuration(hostKey: .trustOnFirstUse { _ in true })
        let tunnel = SSHTunnel(configuration: configuration)
        let endpoint = try await tunnel.start()
        #expect(endpoint.hostKey.fingerprint.hasPrefix("SHA256:"))
        #expect(endpoint.sessionToken.count == 64)

        do {
            // REST: token required on the loopback bind.
            let status = try await SSHTestbed.get(endpoint.baseURL.appending(path: "api/sessions"), headers: [:])
            #expect(status == 401)
            let authorized = try await SSHTestbed.get(
                endpoint.baseURL.appending(path: "api/sessions"), headers: endpoint.restHeaders)
            #expect(authorized == 200)

            // WebSocket chat turn.
            let turn = try await SSHTestbed.chatTurn(url: endpoint.webSocketURL())
            #expect(turn.submitStatus == "streaming")
            #expect(turn.text?.isEmpty == false)

        } catch {
            await tunnel.stop()
            throw error
        }
        await tunnel.stop()
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
        try await connectWebSocket(url: url).executeThenClose { inbound, outbound in
            let rpc = JSONRPC(inbound: inbound.makeAsyncIterator(), outbound: outbound)
            _ = try await rpc.event("gateway.ready")
            _ = try await rpc.call("client.capabilities", ["server_requests": true])
            let session = try await rpc.call("session.create", [:])
            let sessionID = try #require(session["session_id"] as? String)
            let submit = try await rpc.call(
                "prompt.submit", ["session_id": sessionID, "text": "hello [[scenario:text]]"])
            let complete = try await rpc.event("message.complete")
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
