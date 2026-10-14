/// Error codes in JSON-RPC `error` objects.
///
/// The `-32xxx` values are the JSON-RPC 2.0 standard codes. The `4xxx` values are Hermes application codes. Each has
/// its source in `docs/protocol.md`, marked [V] when the testbed produced it, [D] when only the docs name it, and [S]
/// when it comes from upstream source.
public enum HermesErrorCode: Sendable {
    /// Invalid JSON was received (`-32700`). The response id is null.
    public static let parseError = -32700
    /// The request was not a valid JSON-RPC request (`-32600`).
    public static let invalidRequest = -32600
    /// Unknown method (`-32601`). Also the answer to a server request the client does not implement.
    public static let methodNotFound = -32601
    /// Invalid method params (`-32602`).
    public static let invalidParams = -32602
    /// The server failed while handling the request (`-32603`). A handler that throws answers this.
    public static let internalError = -32603

    /// A params model rejected a key it does not know (`4000`) [V].
    public static let unknownParamKey = 4000
    /// Session not found. `session.activate` takes the live id; `session.resume` takes the stored id (`4001`) [V].
    public static let sessionNotFound = 4001
    /// Unknown config key, from `config.get` or `config.set` (`4002`) [V].
    public static let unknownConfigKey = 4002
    /// A param has the wrong type or value (`4004`). For example, `truncate_before_user_ordinal` is a boolean, or an
    /// ordinal was sent without a row id [V].
    public static let invalidArgument = 4004
    /// Session not found, returned by the other lookup path. Same meaning as `4001` (`4007`) [V].
    public static let sessionNotFoundAlternate = 4007
    /// The session is busy. Interrupt, then retry (`4009`) [D].
    public static let sessionBusy = 4009
    /// The user message named by `truncate_before_row_id` is no longer in history. The error `data` has the turn
    /// counts (`4018`) [V].
    public static let targetTurnMissing = 4018
    /// The cut would erase the whole transcript; resend with `confirm_empty_truncate` (`4028`) [V].
    public static let truncateWouldEmptyTranscript = 4028
    /// A truncation was sent without `confirm_truncate` (`4029`) [V].
    public static let truncateNeedsConfirmation = 4029
    /// `truncate_before_user_ordinal` does not match the row id's turn (`4030`) [V].
    public static let truncateOrdinalMismatch = 4030
    /// A deep cut without `confirm_deep_truncate`. The docs say a later release enforces this; this build does not
    /// (`4033`) [D].
    public static let deepTruncateUnconfirmed = 4033
    /// A profile with this name already exists (`4062`) [V].
    public static let profileExists = 4062
    /// A room send was rejected: the same `event_id` with a different payload, or the room's authority is another
    /// gateway (`4111`) [D].
    public static let roomEventRejected = 4111
}
