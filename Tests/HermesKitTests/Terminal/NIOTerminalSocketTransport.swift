import Foundation
import HermesKit
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOWebSocket

/// A `TerminalSocketTransport` on SwiftNIO for live tests, because Linux images lack WebSocket support in
/// `URLSessionWebSocketTask`. Plain `ws://` only. Frames pass through as bytes.
struct NIOTerminalSocketTransport: TerminalSocketTransport {
    private enum Upgrade {
        case websocket(NIOAsyncChannel<WebSocketFrame, WebSocketFrame>)
        case notUpgraded(Int)
    }

    func connect(url: URL, headers: [String: String]) async throws -> any TerminalSocket {
        guard let host = url.host(), let port = url.port else { throw WebSocketError.failed("ws:// URL needs a port") }
        let uri = url.path() + (url.query().map { "?" + $0 } ?? "")
        let upgrade: EventLoopFuture<Upgrade>
        do {
            upgrade = try await ClientBootstrap(group: MultiThreadedEventLoopGroup.singleton)
                .connect(host: host, port: port) { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try Self.configure(channel, host: host, port: port, uri: uri, extra: headers)
                    }
                }
        } catch {
            throw WebSocketError.failed(String(describing: error))
        }
        switch try await upgrade.get() {
        case .websocket(let channel): return NIOTerminalSocket(channel: channel)
        case .notUpgraded(let status): throw WebSocketError.upgradeRejected(status: status)
        }
    }

    private static func configure(
        _ channel: any Channel, host: String, port: Int, uri: String, extra: [String: String]
    ) throws -> EventLoopFuture<Upgrade> {
        let upgrader = NIOTypedWebSocketClientUpgrader<Upgrade>(maxFrameSize: 1 << 24) { channel, _ in
            channel.eventLoop.makeCompletedFuture {
                .websocket(try NIOAsyncChannel(wrappingChannelSynchronously: channel))
            }
        }
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(port)")
        for (name, value) in extra { headers.add(name: name, value: value) }
        let head = HTTPRequestHead(version: .http1_1, method: .GET, uri: uri, headers: headers)
        let configuration = NIOTypedHTTPClientUpgradeConfiguration<Upgrade>(
            upgradeRequestHead: head, upgraders: [upgrader],
            // NIO does not hand over the refusal's response head. The gateway only refuses with 403.
            notUpgradingCompletionHandler: { $0.eventLoop.makeSucceededFuture(.notUpgraded(403)) })
        return try channel.pipeline.syncOperations.configureUpgradableHTTPClientPipeline(
            configuration: .init(upgradeConfiguration: configuration))
    }
}

private final class NIOTerminalSocket: TerminalSocket, Sendable {
    let frames: AsyncThrowingStream<Data, any Error>
    private let outgoing: AsyncStream<Data>.Continuation
    private let pump: Task<Void, Never>

    init(channel: NIOAsyncChannel<WebSocketFrame, WebSocketFrame>) {
        let (stream, incoming) = AsyncThrowingStream<Data, any Error>.makeStream()
        let (queue, outgoing) = AsyncStream<Data>.makeStream()
        frames = stream
        self.outgoing = outgoing
        pump = Task {
            do {
                try await channel.executeThenClose { inbound, writer in
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await bytes in queue {
                                try await writer.write(
                                    WebSocketFrame(
                                        fin: true, opcode: .binary, maskKey: .random(),
                                        data: ByteBuffer(bytes: bytes)))
                            }
                        }
                        group.addTask {
                            for try await frame in inbound {
                                switch frame.opcode {
                                case .binary, .text:
                                    incoming.yield(Data(buffer: frame.data))
                                case .ping:
                                    try await writer.write(
                                        WebSocketFrame(fin: true, opcode: .pong, maskKey: .random(), data: frame.data))
                                case .connectionClose:
                                    incoming.finish()
                                    return
                                default: continue
                                }
                            }
                            incoming.finish()
                        }
                        _ = try await group.next()
                        group.cancelAll()
                    }
                }
            } catch {
                incoming.finish(throwing: WebSocketError.failed(String(describing: error)))
            }
        }
    }

    func send(_ bytes: Data) async throws { outgoing.yield(bytes) }

    func close() async {
        outgoing.finish()
        pump.cancel()
    }
}

extension Data {
    /// The readable bytes of a NIO buffer.
    fileprivate init(buffer: ByteBuffer) {
        self.init(buffer.readableBytesView)
    }
}
