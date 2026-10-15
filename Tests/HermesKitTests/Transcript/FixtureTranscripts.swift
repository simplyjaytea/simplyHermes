import Foundation
import HermesKit

/// Replays one recorded fixture through the transcript reducer, the way the app would: one state per live session.
///
/// Client requests and server responses become the app's own actions (`prompt.submit` → submitted / acknowledged,
/// `session.create|resume|activate` → attached, `session.events.since` → replayed events, answers to server requests
/// → answered).
struct FixtureTranscripts {
    /// Final state per live session id.
    private(set) var sessions: [String: TranscriptState] = [:]
    /// Every action that was applied, per session, in order.
    private(set) var actions: [String: [TranscriptAction]] = [:]
    /// Every `message.complete` payload, per session.
    private(set) var completions: [String: [MessageCompleteEvent]] = [:]

    /// Session the out request with this id was about.
    private var sessionByRequestID: [RPCID: String] = [:]
    /// Server request id to session.
    private var sessionByServerRequestID: [RPCID: String] = [:]

    /// Loaded once per test process.
    nonisolated(unsafe) private static var cache: [FixtureRecord]?

    static func allRecords() throws -> [FixtureRecord] {
        if let cache { return cache }
        let records = try FixtureFiles.load()
        cache = records
        return records
    }

    static func replay(_ file: String, batched: Bool = false) throws -> FixtureTranscripts {
        let records = try allRecords().filter { $0.file == file }
        var replay = FixtureTranscripts()
        for record in records { replay.handle(record) }
        if batched { replay.rebuildBatched() }
        return replay
    }

    /// Re-applies every session's actions in one batch (with coalescing). The result must match one-by-one.
    private mutating func rebuildBatched() {
        for (session, list) in actions {
            var state = TranscriptState(liveSessionID: session)
            state.apply(contentsOf: list)
            sessions[session] = state
        }
    }

    private mutating func apply(_ action: TranscriptAction, to session: String) {
        guard !session.isEmpty else { return }
        var state = sessions[session] ?? TranscriptState(liveSessionID: session)
        state.apply(action)
        sessions[session] = state
        actions[session, default: []].append(action)
    }

    private mutating func handle(_ record: FixtureRecord) {
        switch record.frame {
        case .request(let request) where record.dir == "out":
            handleOutRequest(request)
        case .request(let request):
            guard let serverRequest = try? ServerRequest(request: request) else { return }
            let session = request.params?["session_id"]?.stringValue ?? ""
            sessionByServerRequestID[request.id] = session
            apply(.serverRequest(serverRequest), to: session)
        case .response(let response) where record.dir == "out":
            if let id = response.id, let session = sessionByServerRequestID[id] {
                apply(.requestAnswered(id: id.description), to: session)
            }
        case .response(let response):
            handleResponse(response, method: record.method)
        case .event(let envelope):
            if case .messageComplete(let event) = envelope.event {
                completions[envelope.sessionID, default: []].append(event)
            }
            if envelope.sessionID.isEmpty {
                for session in sessions.keys { apply(.event(envelope, replayed: false), to: session) }
            } else {
                apply(.event(envelope, replayed: false), to: envelope.sessionID)
            }
        case .notification:
            break
        }
    }

    private mutating func handleOutRequest(_ request: RPCRequest) {
        let session = request.params?["session_id"]?.stringValue ?? ""
        sessionByRequestID[request.id] = session
        guard request.method == "prompt.submit", let text = request.params?["text"]?.stringValue else { return }
        let truncate = request.params?["truncate_before_row_id"]?.intValue
        apply(.userSubmitted(localID: request.id.description, text: text, truncateBeforeRowID: truncate), to: session)
    }

    private mutating func handleResponse(_ response: RPCResponse, method: String?) {
        guard let id = response.id, let method else { return }
        let session = sessionByRequestID[id] ?? ""
        switch (method, response.outcome) {
        case ("prompt.submit", .result(let result)):
            guard let ack = try? result.decode(PromptSubmitResult.self) else { return }
            apply(.submitAcknowledged(localID: id.description, ack), to: session)
        case ("prompt.submit", .error(let error)):
            apply(.submitFailed(localID: id.description, message: error.message), to: session)
        case ("session.create", .result(let result)), ("session.resume", .result(let result)),
            ("session.activate", .result(let result)):
            guard let attach = try? result.decode(SessionAttachResult.self) else { return }
            apply(.attached(attach), to: attach.sessionID)
        case ("session.events.since", .result(let result)):
            guard let since = try? result.decode(SessionEventsSinceResult.self) else { return }
            if since.truncated {
                apply(.replayTruncated(latestSeq: since.latestSeq), to: session)
            } else {
                for envelope in since.events { apply(.event(envelope, replayed: true), to: session) }
            }
            for entry in since.openRequests { apply(.openRequestReplayed(entry), to: session) }
        case ("session.history", .result(let result)):
            guard let history = try? result.decode(SessionHistoryResult.self) else { return }
            apply(.history(history.messages), to: session)
        default:
            break
        }
    }
}

extension TranscriptState {
    /// Assistant segments, in order.
    var assistantEntries: [AssistantEntry] {
        items.compactMap { if case .assistant(let entry) = $0.content { entry } else { nil } }
    }

    /// User messages, in order.
    var userEntries: [UserEntry] {
        items.compactMap { if case .user(let entry) = $0.content { entry } else { nil } }
    }

    /// Tool calls, in order.
    var toolEntries: [ToolEntry] {
        items.compactMap { if case .tool(let entry) = $0.content { entry } else { nil } }
    }

    /// Row kinds as short labels, for readable assertions: `user`, `assistant`, `tool:<name>`.
    var shape: [String] {
        items.map { item in
            switch item.content {
            case .user: "user"
            case .assistant: "assistant"
            case .tool(let tool): "tool:\(tool.name)"
            case .other(let role, _): role
            }
        }
    }
}
