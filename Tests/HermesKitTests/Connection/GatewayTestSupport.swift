import Foundation
import HermesKit

/// A clock the test moves by hand. `sleep` returns when `advance(by:)` passes its deadline.
final class ManualClock: GatewayClock, @unchecked Sendable {
    private struct Sleeper {
        var deadline: Double
        var continuation: CheckedContinuation<Void, any Error>
    }

    private let lock = NSLock()
    private var current = 0.0
    private var sleepers: [UUID: Sleeper] = [:]

    func now() -> Double { lock.withLock { current } }

    /// Number of tasks waiting in `sleep`.
    var sleeperCount: Int { lock.withLock { sleepers.count } }

    func sleep(seconds: Double) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let ready = lock.withLock { () -> Bool in
                    if Task.isCancelled { return true }
                    sleepers[id] = Sleeper(deadline: current + seconds, continuation: continuation)
                    return false
                }
                if ready { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = lock.withLock { sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward in steps of at most `step` seconds so timers that arm other timers still fire in order.
    func advance(by seconds: Double, step: Double = 1) async {
        var remaining = seconds
        while remaining > 0 {
            let slice = min(step, remaining)
            remaining -= slice
            let due = lock.withLock { () -> [Sleeper] in
                current += slice
                let ids = sleepers.filter { $0.value.deadline <= current }.map(\.key)
                return ids.compactMap { sleepers.removeValue(forKey: $0) }
            }
            for sleeper in due { sleeper.continuation.resume() }
            await settle()
        }
    }
}

/// Lets other tasks run.
func settle() async {
    for _ in 0..<20 { await Task.yield() }
    try? await Task.sleep(nanoseconds: 2_000_000)
}

/// Polls until `condition` holds. Fails the test by throwing after five real seconds.
func waitUntil(_ what: String, _ condition: @Sendable () -> Bool) async throws {
    for _ in 0..<1000 {
        if condition() { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
    throw TestTimeout(what: what)
}

struct TestTimeout: Error, CustomStringConvertible {
    var what: String
    var description: String { "timed out waiting for \(what)" }
}

/// One frame the client sent.
struct SentFrame: @unchecked Sendable {
    var id: String?
    var method: String?
    var params: [String: Any]?
    var result: [String: Any]?
    var errorCode: Int?
    var text: String
}

/// A fake server end of one WebSocket. The test pushes frames in and reads what the client sent.
final class FakeSocket: WebSocketConnection, @unchecked Sendable {
    let messages: AsyncThrowingStream<String, any Error>
    private let continuation: AsyncThrowingStream<String, any Error>.Continuation
    private let lock = NSLock()
    private var sentFrames: [SentFrame] = []
    private var closedFlag = false
    /// Called for every client frame. Returns frames to push back.
    private var responder: (@Sendable (SentFrame) -> [String])?

    init() {
        (messages, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
    }

    func setResponder(_ responder: @escaping @Sendable (SentFrame) -> [String]) {
        lock.withLock { self.responder = responder }
    }

    var sent: [SentFrame] { lock.withLock { sentFrames } }
    var isClosed: Bool { lock.withLock { closedFlag } }

    func requests(_ method: String) -> [SentFrame] { sent.filter { $0.method == method } }

    func send(_ text: String) async throws {
        if isClosed { throw WebSocketError.closed(code: nil, reason: nil) }
        let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
        let frame = SentFrame(
            id: object["id"] as? String, method: object["method"] as? String,
            params: object["params"] as? [String: Any], result: object["result"] as? [String: Any],
            errorCode: (object["error"] as? [String: Any])?["code"] as? Int, text: text)
        let handler = lock.withLock { () -> (@Sendable (SentFrame) -> [String])? in
            sentFrames.append(frame)
            return responder
        }
        for reply in handler?(frame) ?? [] { push(reply) }
    }

    func close() async {
        lock.withLock { closedFlag = true }
        continuation.finish()
    }

    func push(_ text: String) { continuation.yield(text) }
    func drop(with error: any Error = WebSocketError.failed("network lost")) { continuation.finish(throwing: error) }
}

/// What the next `connect` does.
enum ConnectOutcome: @unchecked Sendable {
    case socket(FakeSocket)
    case reject(Int)
    case fail
    case hang
}

final class FakeTransport: WebSocketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var outcomes: [ConnectOutcome] = []
    private(set) var urls: [URL] = []

    func enqueue(_ outcome: ConnectOutcome) { lock.withLock { outcomes.append(outcome) } }
    var connectURLs: [URL] { lock.withLock { urls } }

    func connect(url: URL, headers: [String: String]) async throws -> any WebSocketConnection {
        let outcome = lock.withLock { () -> ConnectOutcome in
            urls.append(url)
            return outcomes.isEmpty ? .fail : outcomes.removeFirst()
        }
        switch outcome {
        case .socket(let socket): return socket
        case .reject(let status): throw WebSocketError.upgradeRejected(status: status)
        case .fail: throw WebSocketError.failed("refused")
        case .hang:
            try await Task.sleep(nanoseconds: 60_000_000_000)
            throw WebSocketError.failed("hang")
        }
    }
}

/// Collects client events for assertions.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [GatewayClientEvent] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<GatewayClientEvent>) {
        task = Task { [weak self] in
            for await event in stream { self?.lock.withLock { self?.items.append(event) } }
        }
    }

    deinit { task?.cancel() }

    var all: [GatewayClientEvent] { lock.withLock { items } }

    var states: [GatewayConnectionState] {
        all.compactMap { if case .state(let state) = $0 { state } else { nil } }
    }

    /// Delays of every `waitingToReconnect` state, in order.
    var waits: [Double] {
        states.compactMap { if case .waitingToReconnect(_, let delay) = $0 { delay } else { nil } }
    }

    var waitAttempts: [Int] {
        states.compactMap { if case .waitingToReconnect(let attempt, _) = $0 { attempt } else { nil } }
    }

    var deliveredSeqs: [Int] {
        all.compactMap { if case .event(let envelope, _) = $0 { envelope.seq } else { nil } }
    }
}

// MARK: - Frame builders

enum Frames {
    static func ready(epoch: String = "epoch-1", heartbeat: Bool = true) -> String {
        """
        {"jsonrpc":"2.0","method":"event","params":{"type":"gateway.ready","payload":{"skin":{},"change_events":true,\
        "heartbeat":\(heartbeat),"replay_epoch":"\(epoch)"}}}
        """
    }

    static func delta(session: String, seq: Int, text: String = "x") -> String {
        """
        {"jsonrpc":"2.0","method":"event","params":{"type":"message.delta","session_id":"\(session)","seq":\(seq),\
        "payload":{"text":"\(text)"}}}
        """
    }

    static func result(id: String, _ json: String) -> String {
        #"{"jsonrpc":"2.0","id":"\#(id)","result":\#(json)}"#
    }

    static func error(id: String, code: Int, message: String = "boom") -> String {
        #"{"jsonrpc":"2.0","id":"\#(id)","error":{"code":\#(code),"message":"\#(message)"}}"#
    }

    static func serverRequest(id: String, method: String, params: String = "{}") -> String {
        #"{"jsonrpc":"2.0","id":"\#(id)","method":"\#(method)","params":\#(params)}"#
    }

    static func attach(live: String, stored: String) -> String {
        """
        {"session_id":"\(live)","stored_session_id":"\(stored)","message_count":0,"messages":[],"info":{"model":"fake-model",\
        "tools":{},"skills":{},"cwd":"/","branch":"b","project":null,"lazy":true,"desktop_contract":8,"profile_name":"default"}}
        """
    }

    static func since(events: [String], latest: Int, truncated: Bool = false, open: String = "[]") -> String {
        """
        {"events":[\(events.joined(separator: ","))],"latest_seq":\(latest),"truncated":\(truncated),\
        "count":\(events.count),"epoch":"epoch-1","open_requests":\(open)}
        """
    }

    static func rawEvent(session: String, seq: Int, text: String = "x") -> String {
        #"{"type":"message.delta","session_id":"\#(session)","payload":{"text":"\#(text)"},"seq":\#(seq)}"#
    }
}

extension FakeSocket {
    /// Pushes `gateway.ready` and answers `client.capabilities`. Other requests go to `extra`.
    func serve(
        epoch: String = "epoch-1", heartbeat: Bool = true,
        extra: @escaping @Sendable (SentFrame) -> [String] = { _ in [] }
    ) {
        setResponder { frame in
            guard let id = frame.id, let method = frame.method else { return extra(frame) }
            if method == "client.capabilities" { return [Frames.result(id: id, #"{"server_requests":["approval"]}"#)] }
            return extra(frame)
        }
        push(Frames.ready(epoch: epoch, heartbeat: heartbeat))
    }
}
