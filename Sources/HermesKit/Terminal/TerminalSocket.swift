import Foundation

/// One open `/api/pty` socket. Frames are raw bytes in both directions: PTY output comes in, keystrokes and
/// resize escapes go out.
public protocol TerminalSocket: Sendable {
    /// Inbound frames, in order. The stream finishes when the peer closes normally and throws when it closes with
    /// another code or breaks.
    var frames: AsyncThrowingStream<Data, any Error> { get }
    /// Sends one binary frame.
    func send(_ bytes: Data) async throws
    /// Closes the socket. The PTY on the server keeps running until its own timeout. Safe to call more than once.
    func close() async
}

/// Opens `/api/pty` sockets. The app uses ``URLSessionTerminalSocketTransport``; tests script one.
public protocol TerminalSocketTransport: Sendable {
    /// Opens a socket and returns once the HTTP upgrade has succeeded.
    ///
    /// Throws ``WebSocketError/upgradeRejected(status:)`` when the server refuses the upgrade.
    func connect(url: URL, headers: [String: String]) async throws -> any TerminalSocket
}

#if canImport(Darwin)
    import Foundation

    /// Opens `/api/pty` with `URLSessionWebSocketTask`. Frames are delivered as raw bytes, so a UTF-8 sequence split
    /// across two frames still decodes. Apple platforms only: swift-corelibs-foundation cannot do WebSockets.
    public struct URLSessionTerminalSocketTransport: TerminalSocketTransport {
        /// Creates the transport.
        public init() {}

        /// Opens a socket. A refused upgrade throws ``WebSocketError/upgradeRejected(status:)``.
        public func connect(url: URL, headers: [String: String]) async throws -> any TerminalSocket {
            var request = URLRequest(url: url)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let socket = URLSessionTerminalSocket()
            try await socket.open(request)
            return socket
        }
    }

    /// One `URLSessionWebSocketTask`, with its own session so the delegate sees only this socket.
    final class URLSessionTerminalSocket: NSObject, @unchecked Sendable {
        let frames: AsyncThrowingStream<Data, any Error>
        private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
        private let lock = NSLock()
        private var session: URLSession?
        private var task: URLSessionWebSocketTask?
        private var opening: CheckedContinuation<Void, any Error>?
        private var finished = false

        override init() {
            (frames, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
            super.init()
        }

        func open(_ request: URLRequest) async throws {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let task = session.webSocketTask(with: request)
            lock.withLock {
                self.session = session
                self.task = task
            }
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    lock.withLock { opening = continuation }
                    task.resume()
                }
            } onCancel: {
                self.shutdown(code: .goingAway)
                self.resumeOpening(with: .failure(CancellationError()))
            }
            readLoop(task)
        }

        // MARK: - Reading

        private func readLoop(_ task: URLSessionWebSocketTask) {
            Task { [weak self] in
                while true {
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text): self?.continuation.yield(Data(text.utf8))
                        case .data(let data): self?.continuation.yield(data)
                        @unknown default: break
                        }
                    } catch {
                        self?.endStream(error: error, task: task)
                        return
                    }
                }
            }
        }

        private func endStream(error: any Error, task: URLSessionWebSocketTask) {
            let alreadyFinished = lock.withLock {
                let was = finished
                finished = true
                return was
            }
            if alreadyFinished { return }
            if task.closeCode != .invalid && task.closeCode != .normalClosure && task.closeCode != .goingAway {
                let reason = task.closeReason.flatMap { String(bytes: $0, encoding: .utf8) }
                continuation.finish(throwing: WebSocketError.closed(code: task.closeCode.rawValue, reason: reason))
            } else if task.closeCode == .normalClosure || task.closeCode == .goingAway {
                continuation.finish()
            } else {
                continuation.finish(throwing: WebSocketError.failed("\(error)"))
            }
        }
    }

    extension URLSessionTerminalSocket: TerminalSocket {
        func send(_ bytes: Data) async throws {
            guard let task = lock.withLock({ self.task }) else { throw WebSocketError.closed(code: nil, reason: nil) }
            do {
                try await task.send(.data(bytes))
            } catch {
                throw WebSocketError.failed("\(error)")
            }
        }

        func close() async {
            shutdown(code: .normalClosure)
            continuation.finish()
        }
    }

    extension URLSessionTerminalSocket: URLSessionWebSocketDelegate {
        // MARK: - Delegate

        func urlSession(
            _ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?
        ) {
            resumeOpening(with: .success(()))
        }

        func urlSession(
            _ session: URLSession, webSocketTask: URLSessionWebSocketTask,
            didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
            reason: Data?
        ) {
            let text = reason.flatMap { String(bytes: $0, encoding: .utf8) }
            lock.withLock { finished = true }
            if closeCode == .normalClosure || closeCode == .goingAway {
                continuation.finish()
            } else {
                continuation.finish(throwing: WebSocketError.closed(code: closeCode.rawValue, reason: text))
            }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            // Before the socket opened, a refused upgrade lands here with the HTTP response attached.
            if let http = task.response as? HTTPURLResponse, http.statusCode != 101 {
                resumeOpening(with: .failure(WebSocketError.upgradeRejected(status: http.statusCode)))
            } else {
                resumeOpening(with: .failure(WebSocketError.failed(error.map { "\($0)" } ?? "closed before open")))
            }
        }
    }

    extension URLSessionTerminalSocket {
        // MARK: - Helpers

        private func resumeOpening(with result: Result<Void, any Error>) {
            let pending = lock.withLock {
                let value = opening
                opening = nil
                return value
            }
            pending?.resume(with: result)
        }

        private func shutdown(code: URLSessionWebSocketTask.CloseCode) {
            let (task, session) = lock.withLock { (self.task, self.session) }
            task?.cancel(with: code, reason: nil)
            session?.finishTasksAndInvalidate()
        }
    }
#endif
