/// One gateway event, typed by its wire `type`.
///
/// Every event in `docs/protocol/coverage.json` has a typed case. A typed event whose payload does not decode falls
/// back to ``unknown(type:payload:)``, and so does any event type without a case. Decoding never throws for an event
/// payload, so one odd event cannot stall the stream.
public enum GatewayEvent: Sendable, Equatable {
    /// `gateway.ready`: the first frame on every socket.
    case gatewayReady(GatewayReadyEvent)
    /// `session.info`: live session state (model, tools, flags).
    case sessionInfo(SessionInfo)
    /// `session.title`: the title of the session was set.
    case sessionTitle(SessionTitleEvent)
    /// `message.start`: an assistant turn started. Carries no payload.
    case messageStart
    /// `message.delta`: a streamed chunk of assistant text.
    case messageDelta(StreamDelta)
    /// `message.interim`: text written before a tool call.
    case messageInterim(MessageInterimEvent)
    /// `message.complete`: the turn ended, with the final text, usage and durable row ids.
    case messageComplete(MessageCompleteEvent)
    /// `reasoning.available`: the full reasoning text of the turn.
    case reasoningAvailable(StreamDelta)
    /// `reasoning.delta`: a streamed chunk of reasoning text.
    case reasoningDelta(StreamDelta)
    /// `thinking.delta`: cosmetic spinner text such as "formulating...". It is not model reasoning.
    case thinkingDelta(StreamDelta)
    /// `tool.generating`: the model started writing a tool call.
    case toolGenerating(ToolGeneratingEvent)
    /// `tool.start`: a tool call started.
    case toolStart(ToolStartEvent)
    /// `tool.complete`: a tool call finished.
    case toolComplete(ToolCompleteEvent)
    /// `tool.output_risk`: a tool output was flagged.
    case toolOutputRisk(ToolOutputRiskEvent)
    /// `status.update`: a status line, such as the provider retry notice.
    case statusUpdate(StatusUpdateEvent)
    /// `request.cancel`: a server request was answered or cancelled on another socket.
    case requestCancel(RequestCancelEvent)
    /// `approval.cancelled`: pending approvals were cancelled.
    case approvalCancelled(ApprovalCancelledEvent)
    /// `session.reclaimed`: a detached session was reaped.
    case sessionReclaimed(SessionReclaimedEvent)
    /// `sessions.changed`: the session list changed. A global event with no payload.
    case sessionsChanged
    /// `cron.changed`: cron jobs changed. A global event with no payload.
    case cronChanged
    /// `session.usage`: a usage snapshot.
    case sessionUsage(SessionUsageEvent)
    /// `error`: a terminal failure.
    case error(ErrorEvent)
    /// `subagent.start`: a delegated child started.
    case subagentStart(SubagentEvent)
    /// `subagent.thinking`: a delegated child's status text.
    case subagentThinking(SubagentEvent)
    /// `subagent.progress`: a delegated child's progress.
    case subagentProgress(SubagentEvent)
    /// `subagent.tool`: a delegated child used a tool.
    case subagentTool(SubagentEvent)
    /// `subagent.complete`: a delegated child finished.
    case subagentComplete(SubagentEvent)
    /// `todo.updated`: the todo list changed.
    case todoUpdated(TodoUpdatedEvent)
    /// An event type with no typed case, or a typed event whose payload did not decode. The payload is kept as sent.
    case unknown(type: String, payload: JSONValue)

    /// The wire `type` of this event.
    public var typeName: String {
        switch self {
        case .gatewayReady: "gateway.ready"
        case .sessionInfo: "session.info"
        case .sessionTitle: "session.title"
        case .messageStart: "message.start"
        case .messageDelta: "message.delta"
        case .messageInterim: "message.interim"
        case .messageComplete: "message.complete"
        case .reasoningAvailable: "reasoning.available"
        case .reasoningDelta: "reasoning.delta"
        case .thinkingDelta: "thinking.delta"
        case .toolGenerating: "tool.generating"
        case .toolStart: "tool.start"
        case .toolComplete: "tool.complete"
        case .toolOutputRisk: "tool.output_risk"
        case .statusUpdate: "status.update"
        case .requestCancel: "request.cancel"
        case .approvalCancelled: "approval.cancelled"
        case .sessionReclaimed: "session.reclaimed"
        case .sessionsChanged: "sessions.changed"
        case .cronChanged: "cron.changed"
        case .sessionUsage: "session.usage"
        case .error: "error"
        case .subagentStart: "subagent.start"
        case .subagentThinking: "subagent.thinking"
        case .subagentProgress: "subagent.progress"
        case .subagentTool: "subagent.tool"
        case .subagentComplete: "subagent.complete"
        case .todoUpdated: "todo.updated"
        case .unknown(let type, _): type
        }
    }
}

/// A gateway event with its routing fields: `{"type","session_id","payload","seq"}` from `params`, or an element of
/// `session.events.since`.
public struct GatewayEventEnvelope: Sendable, Equatable, Codable {
    /// The JSON-RPC method that carries events.
    public static let method = "event"

    /// The wire event type, such as `message.delta`.
    public var type: String
    /// The live session id. Empty for global events such as `sessions.changed`.
    public var sessionID: String
    /// Per-session, per-server-process sequence number. Nil for global events.
    public var seq: Int?
    /// The typed event.
    public var event: GatewayEvent

    /// Creates an envelope. `type` is taken from the event.
    public init(sessionID: String, seq: Int?, event: GatewayEvent) {
        self.type = event.typeName
        self.sessionID = sessionID
        self.seq = seq
        self.event = event
    }

    /// Decodes `{"type","session_id","payload","seq"}`. `session_id` defaults to empty and `seq` to nil.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: EventWireKey.self)
        let type = try container.decode(String.self, forKey: .type)
        self.type = type
        self.sessionID = try container.decodeIfPresent(String.self, forKey: .sessionID) ?? ""
        self.seq = try container.decodeIfPresent(Int.self, forKey: .seq)
        self.event = GatewayEvent.decode(type: type, from: container)
    }

    /// Encodes the envelope in its wire shape. Typed events write their payload; `message.start` writes `{}`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: EventWireKey.self)
        try container.encode(type, forKey: .type)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encodeIfPresent(seq, forKey: .seq)
        try event.encodePayload(to: container.superEncoder(forKey: .payload))
    }
}

/// Wire keys of an event object.
enum EventWireKey: String, CodingKey {
    case type
    case sessionID = "session_id"
    case payload
    case seq
}

extension GatewayEvent {
    /// Decodes the typed payload for `type`. Falls back to `.unknown` when the type has no case or the payload does
    /// not decode.
    static func decode(type: String, from container: KeyedDecodingContainer<EventWireKey>) -> GatewayEvent {
        switch type {
        case "message.start": return .messageStart
        case "sessions.changed": return .sessionsChanged
        case "cron.changed": return .cronChanged
        case "gateway.ready": return typed(GatewayReadyEvent.self, type, container, GatewayEvent.gatewayReady)
        case "session.info": return typed(SessionInfo.self, type, container, GatewayEvent.sessionInfo)
        case "session.title": return typed(SessionTitleEvent.self, type, container, GatewayEvent.sessionTitle)
        case "message.delta": return typed(StreamDelta.self, type, container, GatewayEvent.messageDelta)
        case "message.interim": return typed(MessageInterimEvent.self, type, container, GatewayEvent.messageInterim)
        case "message.complete": return typed(MessageCompleteEvent.self, type, container, GatewayEvent.messageComplete)
        case "reasoning.available": return typed(StreamDelta.self, type, container, GatewayEvent.reasoningAvailable)
        case "reasoning.delta": return typed(StreamDelta.self, type, container, GatewayEvent.reasoningDelta)
        case "thinking.delta": return typed(StreamDelta.self, type, container, GatewayEvent.thinkingDelta)
        case "tool.generating": return typed(ToolGeneratingEvent.self, type, container, GatewayEvent.toolGenerating)
        case "tool.start": return typed(ToolStartEvent.self, type, container, GatewayEvent.toolStart)
        case "tool.complete": return typed(ToolCompleteEvent.self, type, container, GatewayEvent.toolComplete)
        case "tool.output_risk": return typed(ToolOutputRiskEvent.self, type, container, GatewayEvent.toolOutputRisk)
        case "status.update": return typed(StatusUpdateEvent.self, type, container, GatewayEvent.statusUpdate)
        case "request.cancel": return typed(RequestCancelEvent.self, type, container, GatewayEvent.requestCancel)
        case "approval.cancelled":
            return typed(ApprovalCancelledEvent.self, type, container, GatewayEvent.approvalCancelled)
        case "session.reclaimed":
            return typed(SessionReclaimedEvent.self, type, container, GatewayEvent.sessionReclaimed)
        case "session.usage": return typed(SessionUsageEvent.self, type, container, GatewayEvent.sessionUsage)
        case "error": return typed(ErrorEvent.self, type, container, GatewayEvent.error)
        case "subagent.start": return typed(SubagentEvent.self, type, container, GatewayEvent.subagentStart)
        case "subagent.thinking": return typed(SubagentEvent.self, type, container, GatewayEvent.subagentThinking)
        case "subagent.progress": return typed(SubagentEvent.self, type, container, GatewayEvent.subagentProgress)
        case "subagent.tool": return typed(SubagentEvent.self, type, container, GatewayEvent.subagentTool)
        case "subagent.complete": return typed(SubagentEvent.self, type, container, GatewayEvent.subagentComplete)
        case "todo.updated": return typed(TodoUpdatedEvent.self, type, container, GatewayEvent.todoUpdated)
        default:
            return .unknown(type: type, payload: payloadValue(container))
        }
    }

    /// Decodes the payload as `Payload` and wraps it, or falls back to `.unknown` when it does not decode.
    private static func typed<Payload: Decodable>(
        _ payloadType: Payload.Type,
        _ type: String,
        _ container: KeyedDecodingContainer<EventWireKey>,
        _ wrap: (Payload) -> GatewayEvent
    ) -> GatewayEvent {
        if let decoder = try? container.superDecoder(forKey: .payload) {
            if let payload = try? Payload(from: decoder) { return wrap(payload) }
        }
        return .unknown(type: type, payload: payloadValue(container))
    }

    /// The raw payload, or `.null` when the event has none.
    private static func payloadValue(_ container: KeyedDecodingContainer<EventWireKey>) -> JSONValue {
        (try? container.decodeIfPresent(JSONValue.self, forKey: .payload)) ?? .null
    }

    /// Encodes the payload object for this event. Events with no fields write `{}`.
    func encodePayload(to encoder: any Encoder) throws {
        switch self {
        case .gatewayReady(let payload): try payload.encode(to: encoder)
        case .sessionInfo(let payload): try payload.encode(to: encoder)
        case .sessionTitle(let payload): try payload.encode(to: encoder)
        case .messageStart, .sessionsChanged, .cronChanged: try EmptyEventPayload().encode(to: encoder)
        case .messageDelta(let payload), .reasoningAvailable(let payload), .reasoningDelta(let payload),
            .thinkingDelta(let payload):
            try payload.encode(to: encoder)
        case .messageInterim(let payload): try payload.encode(to: encoder)
        case .messageComplete(let payload): try payload.encode(to: encoder)
        case .toolGenerating(let payload): try payload.encode(to: encoder)
        case .toolStart(let payload): try payload.encode(to: encoder)
        case .toolComplete(let payload): try payload.encode(to: encoder)
        case .toolOutputRisk(let payload): try payload.encode(to: encoder)
        case .statusUpdate(let payload): try payload.encode(to: encoder)
        case .requestCancel(let payload): try payload.encode(to: encoder)
        case .approvalCancelled(let payload): try payload.encode(to: encoder)
        case .sessionReclaimed(let payload): try payload.encode(to: encoder)
        case .sessionUsage(let payload): try payload.encode(to: encoder)
        case .error(let payload): try payload.encode(to: encoder)
        case .subagentStart(let payload), .subagentThinking(let payload), .subagentProgress(let payload),
            .subagentTool(let payload), .subagentComplete(let payload):
            try payload.encode(to: encoder)
        case .todoUpdated(let payload): try payload.encode(to: encoder)
        case .unknown(_, let payload): try payload.encode(to: encoder)
        }
    }
}
