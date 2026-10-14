/// Rewind parameters of `prompt.submit`: archive the turn at `truncateBeforeRowID` and everything after it.
///
/// The server rejects an ordinal without a row id (`4004`), so the row id is always required. The struct always
/// encodes `confirm_truncate: true`, because a truncation without it fails with `4029`. The other keys are written
/// only when set.
public struct PromptTruncate: Sendable, Equatable, Codable {
    /// Durable row id of the user message to cut before.
    public var truncateBeforeRowID: Int
    /// Ordinal of that user turn. Must agree with the row id (`4030` otherwise). Omitted when nil.
    public var truncateBeforeUserOrdinal: Int?
    /// Send `confirm_empty_truncate` when the cut would empty the transcript (`4028` otherwise). Omitted when nil.
    public var confirmEmptyTruncate: Bool?
    /// Send `confirm_deep_truncate` when more than one user turn is archived. Omitted when nil.
    public var confirmDeepTruncate: Bool?

    /// Creates rewind parameters for a row id.
    public init(
        truncateBeforeRowID: Int, truncateBeforeUserOrdinal: Int? = nil, confirmEmptyTruncate: Bool? = nil,
        confirmDeepTruncate: Bool? = nil
    ) {
        self.truncateBeforeRowID = truncateBeforeRowID
        self.truncateBeforeUserOrdinal = truncateBeforeUserOrdinal
        self.confirmEmptyTruncate = confirmEmptyTruncate
        self.confirmDeepTruncate = confirmDeepTruncate
    }

    /// Decodes the truncate keys from a `prompt.submit` object. Returns nil when there is no row id.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PromptWireKey.self)
        guard let rowID = try container.decodeIfPresent(Int.self, forKey: .truncateBeforeRowID) else {
            throw DecodingError.keyNotFound(
                PromptWireKey.truncateBeforeRowID,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "truncate requires a row id"))
        }
        truncateBeforeRowID = rowID
        truncateBeforeUserOrdinal = try container.decodeIfPresent(Int.self, forKey: .truncateBeforeUserOrdinal)
        confirmEmptyTruncate = try container.decodeIfPresent(Bool.self, forKey: .confirmEmptyTruncate)
        confirmDeepTruncate = try container.decodeIfPresent(Bool.self, forKey: .confirmDeepTruncate)
    }

    /// Encodes the truncate keys as a standalone object.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PromptWireKey.self)
        try encode(into: &container)
    }

    /// Writes the truncate keys into the enclosing `prompt.submit` object.
    func encode(into container: inout KeyedEncodingContainer<PromptWireKey>) throws {
        try container.encode(truncateBeforeRowID, forKey: .truncateBeforeRowID)
        try container.encode(true, forKey: .confirmTruncate)
        try container.encodeIfPresent(truncateBeforeUserOrdinal, forKey: .truncateBeforeUserOrdinal)
        try container.encodeIfPresent(confirmEmptyTruncate, forKey: .confirmEmptyTruncate)
        try container.encodeIfPresent(confirmDeepTruncate, forKey: .confirmDeepTruncate)
    }
}

/// Params of `prompt.submit`. `text` starts a turn; `truncate` makes it a rewind.
public struct PromptSubmitParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// The prompt text.
    public var text: String
    /// Profile to scope the call to.
    public var profile: String?
    /// How the UI should display the prompt.
    public var displayKind: String?
    /// Where the prompt came from, for example `desktop`.
    public var surface: String?
    /// Interrupt the running turn first.
    public var interrupted: Bool?
    /// Queue the prompt if the session is busy.
    public var queued: Bool?
    /// Title preview for a new session.
    public var titlePreview: String?
    /// Rewind parameters. Nil for an ordinary prompt.
    public var truncate: PromptTruncate?
    /// Survivor row ids to rebind after a rewind, from the previous result.
    public var rebindSurvivorRowIDs: [Int]?

    /// Creates a prompt. Pass `truncate` only for a rewind.
    public init(
        sessionID: String, text: String, profile: String? = nil, displayKind: String? = nil,
        surface: String? = nil, interrupted: Bool? = nil, queued: Bool? = nil, titlePreview: String? = nil,
        truncate: PromptTruncate? = nil, rebindSurvivorRowIDs: [Int]? = nil
    ) {
        self.sessionID = sessionID
        self.text = text
        self.profile = profile
        self.displayKind = displayKind
        self.surface = surface
        self.interrupted = interrupted
        self.queued = queued
        self.titlePreview = titlePreview
        self.truncate = truncate
        self.rebindSurvivorRowIDs = rebindSurvivorRowIDs
    }

    /// Decodes a `prompt.submit` object. The truncate keys are read from the same object.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: PromptWireKey.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        text = try container.decode(String.self, forKey: .text)
        profile = try container.decodeIfPresent(String.self, forKey: .profile)
        displayKind = try container.decodeIfPresent(String.self, forKey: .displayKind)
        surface = try container.decodeIfPresent(String.self, forKey: .surface)
        interrupted = try container.decodeIfPresent(Bool.self, forKey: .interrupted)
        queued = try container.decodeIfPresent(Bool.self, forKey: .queued)
        titlePreview = try container.decodeIfPresent(String.self, forKey: .titlePreview)
        rebindSurvivorRowIDs = try container.decodeIfPresent([Int].self, forKey: .rebindSurvivorRowIDs)
        truncate = container.contains(.truncateBeforeRowID) ? try PromptTruncate(from: decoder) : nil
    }

    /// Encodes the prompt. Absent optionals are omitted, and a truncation always carries its row id.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: PromptWireKey.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(profile, forKey: .profile)
        try container.encodeIfPresent(displayKind, forKey: .displayKind)
        try container.encodeIfPresent(surface, forKey: .surface)
        try container.encodeIfPresent(interrupted, forKey: .interrupted)
        try container.encodeIfPresent(queued, forKey: .queued)
        try container.encodeIfPresent(titlePreview, forKey: .titlePreview)
        try container.encodeIfPresent(rebindSurvivorRowIDs, forKey: .rebindSurvivorRowIDs)
        try truncate?.encode(into: &container)
    }
}

/// Result of `prompt.submit`.
public struct PromptSubmitResult: Sendable, Equatable, Codable {
    /// How the prompt was handled.
    public var status: PromptSubmitStatus?
    /// Durable row id of the user message. Absent when the prompt was queued.
    public var userRowID: Int?
    /// After a rewind: the row ids that survived the cut. Null entries are kept.
    public var survivorUserRowIDs: [Int?]?
    /// After a rewind: old row id to new row id.
    public var survivorRowIDMap: [String: Int?]?
    /// True when a voice turn was stopped.
    public var voiceStopped: Bool?
    /// Whether turn isolation applied.
    public var turnIsolation: Bool?

    enum CodingKeys: String, CodingKey {
        case status
        case userRowID = "user_row_id"
        case survivorUserRowIDs = "survivor_user_row_ids"
        case survivorRowIDMap = "survivor_row_id_map"
        case voiceStopped = "voice_stopped"
        case turnIsolation = "turn_isolation"
    }
}

/// Wire keys of a `prompt.submit` object, shared by ``PromptSubmitParams`` and ``PromptTruncate``.
enum PromptWireKey: String, CodingKey {
    case sessionID = "session_id"
    case text
    case profile
    case displayKind = "display_kind"
    case surface
    case interrupted
    case queued
    case titlePreview = "title_preview"
    case rebindSurvivorRowIDs = "rebind_survivor_row_ids"
    case truncateBeforeRowID = "truncate_before_row_id"
    case truncateBeforeUserOrdinal = "truncate_before_user_ordinal"
    case confirmTruncate = "confirm_truncate"
    case confirmEmptyTruncate = "confirm_empty_truncate"
    case confirmDeepTruncate = "confirm_deep_truncate"
}
