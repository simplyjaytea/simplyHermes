/// Everything the chat screen reads from a ``ChatSessionController``. Messages that wait for the server live in the
/// outbox (WP-3), not here.
public struct ChatSnapshot: Sendable, Equatable {
    public var transcript: TranscriptState
}
