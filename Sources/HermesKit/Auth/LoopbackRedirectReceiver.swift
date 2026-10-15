#if canImport(Network)
    import Foundation
    import Network

    /// A one-shot HTTP listener on `127.0.0.1:<ephemeral>` that catches the RFC 8252 loopback redirect.
    ///
    /// Runs only while the sign-in sheet is open. Answers the first `GET /cb…` with a short "return to the app"
    /// page, hands its URL to ``redirect()``, and stops. Anything else gets `404`.
    public final class LoopbackRedirectReceiver: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "simplyhermes.loopback-redirect")
        private let lock = NSLock()
        private var continuation: CheckedContinuation<URL, any Error>?
        private var result: Result<URL, any Error>?

        /// The port the listener is bound to. Valid after ``start()``.
        public private(set) var port: Int = 0

        /// Creates a receiver. Nothing listens until ``start()``.
        public init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
            parameters.allowLocalEndpointReuse = true
            listener = try NWListener(using: parameters)
        }

        /// Starts listening and returns the bound port.
        public func start() async throws -> Int {
            let port: Int = try await withCheckedThrowingContinuation { ready in
                let once = OnceFlag()
                listener.stateUpdateHandler = { [weak self] state in
                    switch state {
                    case .ready:
                        if once.set() { ready.resume(returning: Int(self?.listener.port?.rawValue ?? 0)) }
                    case .failed(let error):
                        if once.set() { ready.resume(throwing: error) }
                        self?.finish(.failure(error))
                    default:
                        break
                    }
                }
                listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
                listener.start(queue: queue)
            }
            self.port = port
            return port
        }

        /// Waits for the redirect. Throws ``NativeSignInError/cancelled`` after ``cancel()``.
        public func redirect() async throws -> URL {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(with: result)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }

        /// Stops listening. A pending ``redirect()`` throws ``NativeSignInError/cancelled``.
        public func cancel() {
            finish(.failure(NativeSignInError.cancelled))
        }

        private func finish(_ outcome: Result<URL, any Error>) {
            lock.lock()
            guard result == nil else {
                lock.unlock()
                return
            }
            result = outcome
            let waiting = continuation
            continuation = nil
            lock.unlock()
            listener.cancel()
            waiting?.resume(with: outcome)
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
                guard let self else { return connection.cancel() }
                let target = data.flatMap { Self.requestTarget(in: $0) }
                guard let target, target.hasPrefix(NativeSignInRequest.callbackPath),
                    let url = URL(string: "http://127.0.0.1:\(self.port)\(target)")
                else {
                    return Self.respond(connection, status: "404 Not Found", body: "Not found.")
                }
                Self.respond(
                    connection, status: "200 OK",
                    body: "Signed in. You can return to simplyHermes.")
                self.finish(.success(url))
            }
        }

        /// The target of `GET <target> HTTP/1.1`.
        static func requestTarget(in data: Data) -> String? {
            guard let text = String(data: data.prefix(4096), encoding: .utf8),
                let line = text.split(separator: "\r\n", maxSplits: 1).first
            else { return nil }
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" else { return nil }
            return String(parts[1])
        }

        private static func respond(_ connection: NWConnection, status: String, body: String) {
            let html =
                "<!doctype html><meta name=viewport content=\"width=device-width\">"
                + "<body style=\"font:17px -apple-system;text-align:center;padding:48px\">\(body)</body>"
            let payload = Data(html.utf8)
            let head =
                "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(payload.count)\r\n"
                + "Cache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(
                content: Data(head.utf8) + payload,
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Thread-safe "first caller wins" flag.
    private final class OnceFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func set() -> Bool {
            lock.withLock {
                defer { done = true }
                return !done
            }
        }
    }
#endif
