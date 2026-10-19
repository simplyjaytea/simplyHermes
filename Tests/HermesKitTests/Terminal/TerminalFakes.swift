import Foundation
import HermesKit

/// A socket the test feeds by hand. It records what the app sends.
final class FakeTerminalSocket: TerminalSocket, @unchecked Sendable {
    let frames: AsyncThrowingStream<Data, any Error>
    private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
    private let lock = NSLock()
    private var sentFrames: [Data] = []
    private var closed = false

    init() {
        (frames, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
    }

    var sent: [Data] { lock.withLock { sentFrames } }
    var isClosed: Bool { lock.withLock { closed } }

    func send(_ bytes: Data) async throws {
        lock.withLock { sentFrames.append(bytes) }
    }

    func close() async {
        lock.withLock { closed = true }
        continuation.finish()
    }

    /// Delivers one frame from the server.
    func push(_ bytes: Data) {
        continuation.yield(bytes)
    }

    /// Ends the stream with an error, as a broken socket does.
    func end(throwing error: any Error) {
        continuation.finish(throwing: error)
    }
}

/// Answers each connect with the next scripted outcome and records every URL it was asked to open.
final class ScriptedTerminalTransport: TerminalSocketTransport, @unchecked Sendable {
    enum Outcome {
        case reject(status: Int)
        case accept(FakeTerminalSocket)
    }

    private let lock = NSLock()
    private var outcomes: [Outcome]
    private var urls: [URL] = []

    init(_ outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var connectedURLs: [URL] { lock.withLock { urls } }

    func connect(url: URL, headers: [String: String]) async throws -> any TerminalSocket {
        let outcome: Outcome? = lock.withLock {
            urls.append(url)
            return outcomes.isEmpty ? nil : outcomes.removeFirst()
        }
        switch outcome {
        case .reject(let status)?: throw WebSocketError.upgradeRejected(status: status)
        case .accept(let socket)?: return socket
        case nil: throw WebSocketError.failed("no scripted outcome")
        }
    }
}
