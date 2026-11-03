#if canImport(Darwin)
    import Foundation

    /// Opens WebSockets with `URLSessionWebSocketTask`. Apple platforms only: swift-corelibs-foundation cannot do WebSockets.
    public struct URLSessionWebSocketTransport: WebSocketTransport {
        /// Creates the transport.
        public init() {}

        #if DEBUG
            /// Drops every socket that is open, as a network outage does, so the chat has to reconnect and go through its
            /// real outage path. For the UI tests only (WP-8, AT-1b and AT-3b). New connections are refused by
            /// `NetworkTrap` while the gateway is stopped.
            public static func dropOpenSockets() {
                OpenSocketRegistry.shared.dropAll()
            }
        #endif

        /// Opens a socket. A refused upgrade throws ``WebSocketError/upgradeRejected(status:)``.
        public func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
            var request = URLRequest(url: url)
            for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
            let connection = URLSessionWebSocketConnection()
            try await connection.open(request)
            return connection
        }
    }

    /// One `URLSessionWebSocketTask`, with its own session so the delegate sees only this socket.
    final class URLSessionWebSocketConnection: NSObject, @unchecked Sendable {
        let messages: AsyncThrowingStream<String, any Error>
        private let continuation: AsyncThrowingStream<String, any Error>.Continuation
        private let lock = NSLock()
        private var session: URLSession?
        private var task: URLSessionWebSocketTask?
        private var opening: CheckedContinuation<Void, any Error>?
        private var finished = false

        override init() {
            (messages, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
            super.init()
        }

        func open(_ request: URLRequest) async throws {
            #if DEBUG
                NetworkTrap.record("websocket")
                try NetworkTrap.failIfGatewayStopped()
            #endif
            let session = NetworkSessions.make(configuration: .default, delegate: self, delegateQueue: nil)
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
            #if DEBUG
                OpenSocketRegistry.shared.add(self)
            #endif
            readLoop(task)
        }

        #if DEBUG
            /// Ends the socket as an outage does: the messages stream fails, so the client sees the connection go.
            func drop() {
                shutdown(code: .goingAway)
                continuation.finish(throwing: WebSocketError.failed("the gateway was stopped"))
            }
        #endif

        func send(_ text: String) async throws {
            guard let task = lock.withLock({ self.task }) else { throw WebSocketError.closed(code: nil, reason: nil) }
            do {
                try await task.send(.string(text))
            } catch {
                throw WebSocketError.failed("\(error)")
            }
        }

        func close() async {
            shutdown(code: .normalClosure)
            continuation.finish()
        }

        // MARK: - Reading

        private func readLoop(_ task: URLSessionWebSocketTask) {
            Task { [weak self] in
                while true {
                    do {
                        let message = try await task.receive()
                        switch message {
                        case .string(let text): self?.continuation.yield(text)
                        case .data(let data): self?.continuation.yield((String(bytes: data, encoding: .utf8) ?? ""))
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

    extension URLSessionWebSocketConnection: WebSocketConnection {}

    extension URLSessionWebSocketConnection: URLSessionWebSocketDelegate {
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

    extension URLSessionWebSocketConnection {
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

    #if DEBUG
        /// The sockets opened and not yet closed, held weakly, so a UI test can drop them (`dropOpenSockets`).
        final class OpenSocketRegistry: @unchecked Sendable {
            static let shared = OpenSocketRegistry()

            private final class Weak {
                weak var socket: URLSessionWebSocketConnection?

                init(_ socket: URLSessionWebSocketConnection) { self.socket = socket }
            }

            private let lock = NSLock()
            private var sockets: [Weak] = []

            func add(_ socket: URLSessionWebSocketConnection) {
                lock.withLock {
                    sockets.removeAll { $0.socket == nil }
                    sockets.append(Weak(socket))
                }
            }

            func dropAll() {
                let open = lock.withLock { () -> [URLSessionWebSocketConnection] in
                    let live = sockets.compactMap(\.socket)
                    sockets = []
                    return live
                }
                for socket in open { socket.drop() }
            }
        }
    #endif
#endif
