import Foundation

/// JSON-RPC client for the Hermes gateway WebSocket (`/api/ws`).
///
/// One actor per connection. It opens the socket, completes the handshake (`gateway.ready`, then
/// `client.capabilities`), keeps the link alive with `gateway.ping`, answers server requests through registered
/// handlers, reconnects with full-jitter backoff, and re-attaches tracked sessions after a drop (`session.activate`
/// with the live id, falling back to `session.resume` with the stored id, then `session.events.since`).
///
/// Events reach the owner through ``events()``. See `docs/protocol.md` sections 2, 3, 4 and 6.
public actor GatewayClient {
    private let endpoint: HermesEndpoint
    private let transport: any WebSocketTransport
    private let credentials: GatewayCredentialProvider
    private let clock: any GatewayClock
    /// The sleep between attempts, so ``reconnectNow()`` can end it early.
    private var backoffWait: Task<Void, any Error>?
    private let config: GatewayClientConfig

    private var profile: String?
    private var wanted = false
    private var runTask: Task<Void, Never>?
    private var connection: (any WebSocketConnection)?
    private var generation = 0
    private var handshakeDone = false
    private var state = GatewayConnectionState.idle
    private var subscribers: [UUID: AsyncStream<GatewayClientEvent>.Continuation] = [:]

    private var nextRequestNumber = 1
    private var pending: [RPCID: PendingRequest] = [:]
    private var handlers: [String: GatewayServerRequestHandler] = [:]
    private var handlerTasks: [RPCID: Task<Void, Never>] = [:]

    private var lastInbound = 0.0
    private var lastEpoch: String?
    private var readyEvent: GatewayReadyEvent?
    var sessions: [String: GatewayTrackedSession] = [:]
    var resyncing: Set<String> = []
    var buffered: [String: [GatewayEventEnvelope]] = [:]
    private var setupTask: Task<Void, Never>?

    private struct PendingRequest {
        var method: String
        var continuation: CheckedContinuation<RPCResponse, any Error>
        var timeout: Task<Void, Never>?
    }

    /// Creates a client. Nothing happens until ``start()``.
    public init(
        endpoint: HermesEndpoint,
        transport: any WebSocketTransport,
        credentials: @escaping GatewayCredentialProvider,
        clock: any GatewayClock = SystemGatewayClock(),
        config: GatewayClientConfig = GatewayClientConfig()
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.credentials = credentials
        self.clock = clock
        self.config = config
    }

    // MARK: - Public API

    /// A new stream of client events. Every subscriber gets every event from the moment it subscribes.
    public func events() -> AsyncStream<GatewayClientEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<GatewayClientEvent>.makeStream(bufferingPolicy: .unbounded)
        subscribers[id] = continuation
        continuation.yield(.state(state))
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(id) }
        }
        return stream
    }

    /// The current connection state.
    public var connectionState: GatewayConnectionState { state }

    /// Starts connecting. Does nothing when already started. After ``GatewayConnectionState/failed(_:)`` it tries again.
    public func start() {
        guard !wanted else { return }
        wanted = true
        runTask = Task { await self.runLoop() }
    }

    /// Stops the client, closes the socket and fails pending requests with ``GatewayClientError/stopped``.
    public func stop() async {
        wanted = false
        runTask?.cancel()
        runTask = nil
        await dropConnection(error: GatewayClientError.stopped)
        setState(.stopped)
    }

    /// Registers the handler for a server-to-client request method such as `approval`. Replaces a previous one.
    /// A request with no handler is answered `-32601` so the agent fails fast.
    public func setServerRequestHandler(method: String, handler: @escaping GatewayServerRequestHandler) {
        handlers[method] = handler
    }

    /// Removes a handler.
    public func removeServerRequestHandler(method: String) {
        handlers[method] = nil
    }

    /// Starts tracking a session so it is re-attached and replayed after a reconnect.
    /// `watermark` is the last `seq` already shown. Nil means none. `profile` is the profile the session was resumed
    /// under; the re-attach calls carry it, so they never follow a profile change made in the meantime.
    public func track(liveID: String, storedID: String, watermark: Int? = nil, profile: String? = nil) {
        sessions[liveID] = GatewayTrackedSession(
            liveID: liveID, storedID: storedID, watermark: watermark, profile: profile)
    }

    /// Stops tracking a session.
    public func untrack(liveID: String) {
        sessions[liveID] = nil
        buffered[liveID] = nil
        resyncing.remove(liveID)
    }

    /// The last `seq` delivered for a tracked session.
    public func watermark(liveID: String) -> Int? {
        sessions[liveID]?.watermark
    }

    /// Sets the active profile. Every later call to a method that takes `profile` carries it unless the caller set one.
    public func setProfile(_ name: String?) { profile = name }

    /// The active profile, if one is set.
    public func activeProfile() -> String? { profile }

    /// Sends a request and returns the raw response. Error responses are returned, not thrown.
    public func send(method: String, params: JSONValue? = nil, timeout: Double? = nil) async throws -> RPCResponse {
        guard connection != nil, handshakeDone || method == "client.capabilities" else {
            throw GatewayClientError.notConnected
        }
        let scoped = ProfileScope.scoped(method: method, params: params, profile: profile)
        return try await sendRaw(method: method, params: scoped, timeout: timeout)
    }

    /// Calls a method and decodes `result`. Throws ``RPCError`` for an error response.
    public func call<Result: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)? = nil, as type: Result.Type = Result.self,
        timeout: Double? = nil
    ) async throws -> Result {
        let encoded = try params.map { try JSONValue(encoding: $0) }
        let response = try await send(method: method, params: encoded, timeout: timeout)
        if let error = response.error { throw error }
        guard let value = try response.decodeResult(type) else {
            throw DecodingError.valueNotFound(
                Result.self, .init(codingPath: [], debugDescription: "response to \(method) has no result"))
        }
        return value
    }

    // MARK: - Run loop

    private func runLoop() async {
        var attempt = 0
        var credentialRequest = GatewayCredentialRequest.initial
        while wanted && !Task.isCancelled {
            setState(.connecting(attempt: attempt))
            var openedAt: Double?
            do {
                let credential: GatewayCredential
                do {
                    credential = try await credentials(credentialRequest)
                } catch is GatewaySignInRequired {
                    failAndStop(.signInRequired)
                    return
                } catch is CredentialStoreError {
                    // A Keychain failure does not pass by waiting, so the loop does not retry it.
                    failAndStop(.credentialsUnavailable)
                    return
                }
                let url = webSocketURL(for: credential)
                let socket = try await openSocket(url: url)
                credentialRequest = .initial
                openedAt = clock.now()
                try await runConnection(socket)
            } catch is CancellationError {
                return
            } catch WebSocketError.upgradeRejected(status: 403) {
                switch credentialRequest {
                case .initial:
                    credentialRequest = .afterRejection
                    continue
                case .afterRejection:
                    credentialRequest = .reauthenticate
                    continue
                case .reauthenticate:
                    failAndStop(.authenticationRejected)
                    return
                }
            } catch {
                // Network error, timeout, close, proxy error: back off and retry.
            }
            guard wanted && !Task.isCancelled else { return }
            if let openedAt, clock.now() - openedAt >= config.reconnect.minStableUptime {
                attempt = 0
            } else {
                attempt += 1
            }
            let delay = config.reconnect.delay(attempt: max(attempt - 1, 0))
            setState(.waitingToReconnect(attempt: attempt, delay: delay))
            // The wait can be cut short by ``reconnectNow()``. A cancelled run loop still ends it.
            let wait = Task { [clock] in try await clock.sleep(seconds: delay) }
            backoffWait = wait
            do {
                try await withTaskCancellationHandler {
                    try await wait.value
                } onCancel: {
                    wait.cancel()
                }
            } catch {
                if Task.isCancelled { return }
            }
            backoffWait = nil
        }
    }

    /// Skips the backoff wait and connects now, for the moments a waiting client has good reason to try again: the app
    /// came back to the foreground, or the network path came back (WP-12). Does nothing unless the client is waiting to
    /// reconnect: a connected or connecting client has nothing to skip, and a stopped one stays stopped.
    public func reconnectNow() {
        guard wanted, case .waitingToReconnect = state else { return }
        backoffWait?.cancel()
    }

    private func failAndStop(_ failure: GatewayFailure) {
        wanted = false
        runTask = nil
        setState(.failed(failure))
    }

    private func webSocketURL(for credential: GatewayCredential) -> URL {
        switch credential {
        case .ticket(let ticket): endpoint.webSocketURL(path: config.path, ticket: ticket)
        case .token(let token): endpoint.webSocketURL(path: config.path, token: token)
        case .none: endpoint.webSocketURL(path: config.path)
        }
    }

    private func openSocket(url: URL) async throws -> any WebSocketConnection {
        let transport = self.transport
        let headers = endpoint.headers
        let timeout = config.connectTimeout
        let clock = self.clock
        return try await withThrowingTaskGroup(of: (any WebSocketConnection)?.self) { group in
            group.addTask { try await transport.connect(url: url, headers: headers) }
            group.addTask {
                try await clock.sleep(seconds: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw WebSocketError.failed("no result") }
            guard let socket = first else { throw WebSocketError.failed("connect timed out") }
            return socket
        }
    }

    /// Runs one connection until it ends. Throws the reason it ended.
    private func runConnection(_ socket: any WebSocketConnection) async throws {
        generation += 1
        let myGeneration = generation
        connection = socket
        handshakeDone = false
        readyEvent = nil
        lastInbound = clock.now()
        defer {
            if generation == myGeneration {
                Task { await self.connectionEnded(generation: myGeneration) }
            }
        }
        let silenceDeadline = config.silenceDeadline
        let heartbeatInterval = config.heartbeatInterval
        let connectTimeout = config.connectTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await text in socket.messages {
                    await self.receive(text, generation: myGeneration)
                }
                throw WebSocketError.closed(code: nil, reason: nil)
            }
            group.addTask {
                // Watchdog, one tick per heartbeat interval: the handshake must finish within the connect timeout,
                // then any inbound frame within the silence deadline keeps the socket alive.
                let started = self.clock.now()
                while true {
                    try await self.clock.sleep(seconds: heartbeatInterval)
                    guard await self.isHandshakeDone(generation: myGeneration) else {
                        if self.clock.now() - started >= connectTimeout {
                            throw WebSocketError.failed("gateway.ready did not arrive")
                        }
                        continue
                    }
                    let silent = await self.secondsSinceInbound()
                    if silent >= silenceDeadline { throw WebSocketError.failed("no frames for \(Int(silent)) s") }
                    await self.sendHeartbeatIfRequested(generation: myGeneration)
                }
            }
            defer { group.cancelAll() }
            _ = try await group.next()
        }
    }

    private func connectionEnded(generation ended: Int) async {
        guard generation == ended else { return }
        await dropConnection(error: GatewayClientError.disconnected)
    }

    private func dropConnection(error: any Error) async {
        let socket = connection
        connection = nil
        handshakeDone = false
        setupTask?.cancel()
        setupTask = nil
        resyncing.removeAll()
        buffered.removeAll()
        for (_, task) in handlerTasks { task.cancel() }
        handlerTasks.removeAll()
        let waiting = pending
        pending.removeAll()
        for (_, request) in waiting {
            request.timeout?.cancel()
            request.continuation.resume(throwing: error)
        }
        await socket?.close()
    }

    private func isHandshakeDone(generation expected: Int) -> Bool {
        generation == expected && handshakeDone
    }

    private func secondsSinceInbound() -> Double {
        clock.now() - lastInbound
    }

    private func sendHeartbeatIfRequested(generation expected: Int) async {
        guard generation == expected, readyEvent?.heartbeat == true, let socket = connection else { return }
        let request = RPCRequest(id: allocateID(), method: "gateway.ping", params: nil)
        if let text = encode(request) { try? await socket.send(text) }
    }

    // MARK: - Inbound frames

    private func receive(_ text: String, generation expected: Int) async {
        guard generation == expected else { return }
        lastInbound = clock.now()
        guard let data = text.data(using: .utf8), let frame = try? JSONDecoder().decode(RPCFrame.self, from: data)
        else {
            return
        }
        switch frame {
        case .response(let response):
            resolve(response)
        case .event(let envelope):
            await handleEvent(envelope)
        case .request(let request):
            handleServerRequest(request, generation: expected)
        case .notification:
            break
        }
    }

    private func resolve(_ response: RPCResponse) {
        guard let id = response.id, let request = pending.removeValue(forKey: id) else { return }
        request.timeout?.cancel()
        request.continuation.resume(returning: response)
    }

    private func handleEvent(_ envelope: GatewayEventEnvelope) async {
        switch envelope.event {
        case .gatewayReady(let ready):
            readyEvent = ready
            emit(.ready(ready))
            let expected = generation
            setupTask = Task { await self.performHandshake(ready: ready, generation: expected) }
            return
        case .requestCancel(let cancel):
            if let task = handlerTasks.removeValue(forKey: RPCID.string(cancel.id)) { task.cancel() }
        case .sessionReclaimed(let reclaimed):
            if var tracked = sessions[reclaimed.sessionID], reclaimed.reason != "ws_orphan_reap" || handshakeDone {
                tracked.reclaimed = true
                sessions[reclaimed.sessionID] = tracked
                emit(
                    .sessionReclaimed(
                        liveID: reclaimed.sessionID, storedID: reclaimed.storedSessionID, reason: reclaimed.reason))
            }
        default:
            break
        }
        deliverLive(envelope)
    }

    /// Delivers a live event, gated by the session watermark, or buffers it while that session is re-attaching.
    private func deliverLive(_ envelope: GatewayEventEnvelope) {
        let id = envelope.sessionID
        if resyncing.contains(id) {
            buffered[id, default: []].append(envelope)
            return
        }
        deliver(envelope, replayed: false)
    }

    func deliver(_ envelope: GatewayEventEnvelope, replayed: Bool) {
        if var tracked = sessions[envelope.sessionID], let seq = envelope.seq {
            if let mark = tracked.watermark, seq <= mark { return }
            tracked.watermark = seq
            sessions[envelope.sessionID] = tracked
        }
        emit(.event(envelope, replayed: replayed))
    }

    // MARK: - Server requests

    private func handleServerRequest(_ request: RPCRequest, generation expected: Int) {
        guard let handler = handlers[request.method] else {
            Task { await self.respond(.methodNotFound(id: request.id, method: request.method), generation: expected) }
            return
        }
        let id = request.id
        handlerTasks[id] = Task {
            let response: RPCResponse
            do {
                response = RPCResponse(id: id, result: try await handler(request))
            } catch is CancellationError {
                self.finishHandler(id)
                return
            } catch {
                response = RPCResponse(id: id, error: RPCError(code: -32603, message: "\(error)"))
            }
            await self.respond(response, generation: expected)
            self.finishHandler(id)
        }
    }

    private func finishHandler(_ id: RPCID) {
        handlerTasks[id] = nil
    }

    private func respond(_ response: RPCResponse, generation expected: Int) async {
        guard generation == expected, let socket = connection, let text = encode(response) else { return }
        try? await socket.send(text)
    }

    // MARK: - Handshake and resync

    private func performHandshake(ready: GatewayReadyEvent, generation expected: Int) async {
        do {
            let reply = try await sendRaw(
                method: "client.capabilities", params: .object(["server_requests": .bool(true)]), timeout: nil)
            if let error = reply.error { throw error }
        } catch {
            if generation == expected { await closeForFailure() }
            return
        }
        guard generation == expected, !Task.isCancelled else { return }
        let restarted = lastEpoch != nil && lastEpoch != ready.replayEpoch
        lastEpoch = ready.replayEpoch
        handshakeDone = true
        setState(.connected)
        if restarted { emit(.serverRestarted) }
        for liveID in Array(sessions.keys) where sessions[liveID]?.reclaimed == false {
            guard generation == expected, !Task.isCancelled else { return }
            await resync(liveID: liveID, forceCold: restarted)
        }
    }

    private func closeForFailure() async {
        let socket = connection
        await socket?.close()
    }

    // MARK: - Requests

    private func allocateID() -> RPCID {
        defer { nextRequestNumber += 1 }
        return .string("c\(nextRequestNumber)")
    }

    func sendRaw(method: String, params: JSONValue?, timeout: Double?) async throws -> RPCResponse {
        guard let socket = connection else { throw GatewayClientError.notConnected }
        let id = allocateID()
        let request = RPCRequest(id: id, method: method, params: params)
        guard let text = encode(request) else { throw GatewayClientError.notConnected }
        let limit =
            timeout ?? (method == "approval.respond" ? config.approvalRespondTimeout : config.requestTimeout)
        let clock = self.clock
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RPCResponse, any Error>) in
                let timer = Task { [weak self] in
                    do { try await clock.sleep(seconds: limit) } catch { return }
                    await self?.timeOut(id: id, method: method)
                }
                pending[id] = PendingRequest(method: method, continuation: continuation, timeout: timer)
                Task {
                    do { try await socket.send(text) } catch { self.failPending(id: id, error: error) }
                }
            }
        } onCancel: {
            Task { await self.failPending(id: id, error: CancellationError()) }
        }
    }

    private func timeOut(id: RPCID, method: String) {
        failPending(id: id, error: GatewayClientError.timedOut(method: method))
    }

    private func failPending(id: RPCID, error: any Error) {
        guard let request = pending.removeValue(forKey: id) else { return }
        request.timeout?.cancel()
        request.continuation.resume(throwing: error)
    }

    // MARK: - Helpers

    private func encode<Value: Encodable>(_ value: Value) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setState(_ new: GatewayConnectionState) {
        guard new != state else { return }
        state = new
        emit(.state(new))
    }

    func emit(_ event: GatewayClientEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }
}

/// What the client keeps about one live session it must re-attach after a reconnect. Lives outside the actor so the
/// actor body stays under the lint limit.
struct GatewayTrackedSession {
    var liveID: String
    var storedID: String
    var watermark: Int?
    /// The profile the session was resumed under. A re-attach uses it, not the client's current profile (WP-5).
    var profile: String?
    var reclaimed = false
}
