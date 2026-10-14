import NIOCore
import NIOPosix
import Testing

@testable import HermesSSH

/// Echoes every byte back.
private final class EchoHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer
    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        context.writeAndFlush(data, promise: nil)
    }
}

/// Collects bytes until `expected` have arrived.
private final class CollectHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    private var received = ByteBuffer()
    private let expected: Int
    private let done: EventLoopPromise<String>

    init(expected: Int, done: EventLoopPromise<String>) {
        self.expected = expected
        self.done = done
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)
        received.writeBuffer(&buffer)
        if received.readableBytes >= expected {
            done.succeed(String(buffer: received))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        done.fail(ChannelError.eof)
    }
}

@Suite struct LoopbackForwarderTests {
    @Test func forwardsBytesBothWaysOverLoopback() async throws {
        let loop = MultiThreadedEventLoopGroup.singleton.next()
        let echo = try await ServerBootstrap(group: loop)
            .childChannelInitializer { $0.pipeline.addHandler(EchoHandler()) }
            .bind(host: "127.0.0.1", port: 0).get()
        let echoPort = try #require(echo.localAddress?.port)

        let forwarder = try await LoopbackForwarder.start(on: loop) { initialize in
            try await ClientBootstrap(group: loop)
                .channelInitializer(initialize)
                .connect(host: "127.0.0.1", port: echoPort).get()
        }
        #expect(forwarder.port != echoPort)

        // Two concurrent clients, each with its own upstream.
        for message in ["hello through the tunnel", "second connection"] {
            let done = loop.makePromise(of: String.self)
            let client = try await ClientBootstrap(group: loop)
                .channelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.addHandler(
                            CollectHandler(expected: message.utf8.count, done: done))
                    }
                }
                .connect(host: "127.0.0.1", port: forwarder.port).get()
            try await client.writeAndFlush(ByteBuffer(string: message))
            #expect(try await done.futureResult.get() == message)
            try await client.close()
        }

        await forwarder.stop()
        try await echo.close()
    }

    @Test func closesClientWhenUpstreamFails() async throws {
        let loop = MultiThreadedEventLoopGroup.singleton.next()
        let forwarder = try await LoopbackForwarder.start(on: loop) { _ in
            throw SSHTunnelError.notConnected
        }
        let client = try await ClientBootstrap(group: loop)
            .connect(host: "127.0.0.1", port: forwarder.port).get()
        try await client.closeFuture.get()
        await forwarder.stop()
    }
}
