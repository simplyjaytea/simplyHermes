/// Merges bursts of streaming deltas so the transcript updates once per batch instead of once per frame.
///
/// The server already batches deltas to about 30 per second; a replay after a reconnect can deliver hundreds at
/// once. Merging keeps the result identical to applying each delta in turn.
public enum TranscriptCoalescer {
    /// Merges runs of consecutive `message.delta` or `reasoning.delta` events for one session into one event with
    /// the joined text and the last `seq`. A run of `thinking.delta` keeps only its last event, since each replaces
    /// the previous spinner text. Every other action passes through in order.
    public static func coalesce(_ actions: [TranscriptAction]) -> [TranscriptAction] {
        var output: [TranscriptAction] = []
        output.reserveCapacity(actions.count)
        for action in actions {
            if let last = output.last, let merged = merge(last, action) {
                output[output.count - 1] = merged
            } else {
                output.append(action)
            }
        }
        return output
    }

    private static func merge(_ first: TranscriptAction, _ second: TranscriptAction) -> TranscriptAction? {
        guard case .event(let lhs, let replayed) = first, case .event(let rhs, let rhsReplayed) = second,
            replayed == rhsReplayed, lhs.sessionID == rhs.sessionID
        else { return nil }
        if let lhsSeq = lhs.seq, let rhsSeq = rhs.seq, rhsSeq <= lhsSeq { return nil }
        let event: GatewayEvent
        switch (lhs.event, rhs.event) {
        case (.messageDelta(let head), .messageDelta(let tail)) where head.rendered == nil && tail.rendered == nil:
            event = .messageDelta(StreamDelta(text: head.text + tail.text))
        case (.reasoningDelta(let head), .reasoningDelta(let tail)) where head.rendered == nil && tail.rendered == nil:
            event = .reasoningDelta(StreamDelta(text: head.text + tail.text))
        case (.thinkingDelta, .thinkingDelta):
            event = rhs.event
        default:
            return nil
        }
        return .event(
            GatewayEventEnvelope(sessionID: rhs.sessionID, seq: rhs.seq ?? lhs.seq, event: event), replayed: replayed)
    }
}

extension TranscriptAction {
    /// The transcript action for a client event, or nil when the transcript does not need it.
    ///
    /// A live re-attach maps to nil on purpose: the replayed events already filled the gap, and rebuilding from the
    /// attach result would show the streamed text twice. A cold re-attach rebuilds the state.
    public init?(_ event: GatewayClientEvent) {
        switch event {
        case .event(let envelope, let replayed): self = .event(envelope, replayed: replayed)
        case .sessionReattached(_, let result, .cold): self = .attached(result)
        case .replayTruncated(_, let latestSeq): self = .replayTruncated(latestSeq: latestSeq)
        case .openRequestReplayed(_, let request): self = .openRequestReplayed(request)
        default: return nil
        }
    }
}
