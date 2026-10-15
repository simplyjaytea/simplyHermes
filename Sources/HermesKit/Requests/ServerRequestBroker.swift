import Foundation

/// The user's answer to a pending server request.
public enum ServerAnswer: Sendable, Equatable {
    /// Answer to `approval`.
    case approval(ApprovalAnswer)
    /// Answer to `clarify`, one entry per question id.
    case clarify(ClarifyAnswer)
    /// Answer to `sudo` or `secret`.
    case value(ValueAnswer)
}

/// Why ``ServerRequestBroker/answer(_:with:)`` refused an answer.
public enum ServerRequestError: Error, Equatable, Sendable {
    /// No pending request has this id. It was answered or cancelled already.
    case notPending(String)
    /// The answer type does not fit the request method.
    case wrongAnswer(method: String)
    /// A clarify answer names a question the request does not have, or an empty answer for a choice question.
    case invalidClarifyAnswer(qid: String)
    /// A `sudo` or `secret` answer holds an empty value.
    case emptyValue
}

/// Holds server-to-client requests (`approval`, `clarify`, `sudo`, `secret`) until the user answers.
///
/// ``install(on:)`` registers the four handlers on a ``GatewayClient``. A handler suspends until ``answer(_:with:)``
/// is called, or until the client cancels it (`request.cancel`, a dropped socket), which removes the request from
/// ``pending`` without sending a reply. The broker keeps no answer and no secret after resuming the handler.
public actor ServerRequestBroker {
    /// The methods the broker handles.
    public static let methods = ["approval", "clarify", "sudo", "secret"]

    private struct Waiter {
        var pending: PendingServerRequest
        var resume: CheckedContinuation<JSONValue, any Error>
    }

    private var waiters: [String: Waiter] = [:]
    private var order: [String] = []
    private var observers: [UUID: AsyncStream<[PendingServerRequest]>.Continuation] = [:]

    /// Creates a broker with nothing pending.
    public init() {}

    /// Registers the handlers on `client`. Call before the client starts so no request is answered `-32601`.
    public func install(on client: GatewayClient) async {
        for method in Self.methods {
            await client.setServerRequestHandler(method: method) { [self] request in
                try await handle(request)
            }
        }
    }

    /// The requests waiting for the user, oldest first.
    public var pending: [PendingServerRequest] { order.compactMap { waiters[$0]?.pending } }

    /// A stream of the pending list, starting with the current one and then after every change.
    public func updates() -> AsyncStream<[PendingServerRequest]> {
        let (stream, continuation) = AsyncStream<[PendingServerRequest]>.makeStream(
            bufferingPolicy: .bufferingNewest(1))
        let token = UUID()
        observers[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(token) }
        }
        continuation.yield(pending)
        return stream
    }

    /// Handles one request: waits for the answer and returns it as the JSON-RPC result.
    ///
    /// Throws ``CancellationError`` when the task is cancelled, and the decoding error when the params of a known
    /// method are malformed (the client then replies `-32603`).
    public func handle(_ request: RPCRequest) async throws -> JSONValue {
        let parsed = try ServerRequest(request: request)
        guard case .unknown = parsed else {
            let id = Self.key(request.id)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    add(Waiter(pending: .init(id: id, request: parsed, replayed: false), resume: continuation))
                }
            } onCancel: {
                Task { await self.drop(id, error: CancellationError()) }
            }
        }
        throw RPCError(code: -32601, message: "Method not found: \(request.method)")
    }

    /// Answers a pending request. The handler returns the answer to the server.
    public func answer(_ id: String, with answer: ServerAnswer) throws {
        guard let waiter = waiters[id] else { throw ServerRequestError.notPending(id) }
        let result = try Self.result(for: answer, request: waiter.pending.request)
        remove(id)
        waiter.resume.resume(returning: result)
    }

    /// Drops a request that the server cancelled (`request.cancel`) or that another client answered.
    public func cancel(_ id: String) {
        drop(id, error: CancellationError())
    }

    /// Drops every request, for a closed session or a dropped connection.
    public func cancelAll() {
        for id in order { drop(id, error: CancellationError()) }
    }

    // MARK: - Private

    private func add(_ waiter: Waiter) {
        waiters[waiter.pending.id] = waiter
        order.append(waiter.pending.id)
        publish()
    }

    private func drop(_ id: String, error: any Error) {
        guard let waiter = waiters[id] else { return }
        remove(id)
        waiter.resume.resume(throwing: error)
    }

    private func remove(_ id: String) {
        waiters[id] = nil
        order.removeAll { $0 == id }
        publish()
    }

    private func publish() {
        let list = pending
        for observer in observers.values { observer.yield(list) }
    }

    private func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    private static func key(_ id: RPCID) -> String {
        switch id {
        case .string(let value): value
        case .int(let value): String(value)
        }
    }

    private static func result(for answer: ServerAnswer, request: ServerRequest) throws -> JSONValue {
        switch (request, answer) {
        case (.approval, .approval(let value)):
            return try JSONValue(encoding: value)
        case (.clarify(_, let clarify), .clarify(let value)):
            let questions = Dictionary(uniqueKeysWithValues: clarify.questions.map { ($0.qid, $0) })
            for (qid, text) in value.answers.sorted(by: { $0.key < $1.key }) {
                guard let question = questions[qid], !text.isEmpty || question.choices == nil else {
                    throw ServerRequestError.invalidClarifyAnswer(qid: qid)
                }
            }
            return try JSONValue(encoding: value)
        case (.sudo, .value(let value)), (.secret, .value(let value)):
            guard !value.value.isEmpty else { throw ServerRequestError.emptyValue }
            return try JSONValue(encoding: value)
        default:
            throw ServerRequestError.wrongAnswer(method: method(of: request))
        }
    }

    private static func method(of request: ServerRequest) -> String {
        switch request {
        case .approval: "approval"
        case .clarify: "clarify"
        case .sudo: "sudo"
        case .secret: "secret"
        case .unknown(_, let method, _): method
        }
    }
}
