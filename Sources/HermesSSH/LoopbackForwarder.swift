import NIOCore
import NIOPosix

/// Listens on `127.0.0.1:<ephemeral>` and joins every accepted connection to a new upstream channel
/// (in SSH mode, one `direct-tcpip` channel to the remote dashboard). No Host rewrite: the dashboard accepts
/// any loopback Host header (docs/protocol.md section 8).
///
/// The listener runs on the upstream's event loop so each pair of channels shares one loop.
public final class LoopbackForwarder: Sendable {
    /// Opens one upstream channel and runs `initialize` on it (on the upstream's event loop) before it is used.
    public typealias Connector =
        @Sendable (_ initialize: @escaping @Sendable (Channel) -> EventLoopFuture<Void>) async throws -> Channel

    private let serverChannel: Channel

    /// The local port clients connect to.
    public let port: Int

    private init(serverChannel: Channel, port: Int) {
        self.serverChannel = serverChannel
        self.port = port
    }

    /// Starts listening. `eventLoop` must be the loop the connector's channels live on.
    public static func start(
        on eventLoop: EventLoop, connector: @escaping Connector
    ) async throws -> LoopbackForwarder {
        let channel = try await ServerBootstrap(group: eventLoop)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(.allowRemoteHalfClosure, value: true)
            .childChannelInitializer { inbound in
                let promise = inbound.eventLoop.makePromise(of: Void.self)
                do {
                    let (local, remote) = GlueHandler.matchedPair()
                    try inbound.pipeline.syncOperations.addHandler(local)
                    let remoteHandler = NIOLoopBound(remote, eventLoop: inbound.eventLoop)
                    promise.completeWithTask {
                        _ = try await connector { upstream in
                            upstream.eventLoop.makeCompletedFuture {
                                try upstream.pipeline.syncOperations.addHandler(remoteHandler.value)
                            }
                        }
                    }
                } catch {
                    promise.fail(error)
                }
                return promise.futureResult
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()
        guard let port = channel.localAddress?.port else {
            try? await channel.close()
            throw SSHTunnelError.notConnected
        }
        return LoopbackForwarder(serverChannel: channel, port: port)
    }

    /// Stops accepting. Open connections close when their upstream closes.
    public func stop() async {
        try? await serverChannel.close()
    }
}
