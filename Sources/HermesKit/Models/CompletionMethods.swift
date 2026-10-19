/// Params of `complete.slash`: ranked slash command and skill completions for a `/` token.
public struct CompleteSlashParams: Sendable, Equatable, Codable {
    /// The token, starting with `/`.
    public var text: String
    /// Session the completions are for. Skills resolve against its profile and workspace.
    public var sessionID: String?
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates the params.
    public init(text: String, sessionID: String? = nil, profile: String? = nil) {
        self.text = text
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case text, profile
        case sessionID = "session_id"
    }
}

/// Params of `complete.path`: file, folder and `@` reference completions for the token under the caret.
public struct CompletePathParams: Sendable, Equatable, Codable {
    /// The token under the caret. An `@` prefix asks for a context reference.
    public var word: String
    /// Session whose workspace the paths resolve against.
    public var sessionID: String?
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates the params.
    public init(word: String, sessionID: String? = nil, profile: String? = nil) {
        self.word = word
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case word, profile
        case sessionID = "session_id"
    }
}

/// One row of a completion popover.
public struct CompletionItem: Sendable, Equatable, Codable {
    /// Text to insert.
    public var text: String
    /// Label to show. Empty means the label is `text`.
    public var display: String
    /// Short description, or where the item sits.
    public var meta: String
    /// `command` or `skill` for a slash completion. Nil otherwise.
    public var kind: String?

    /// The label the popover shows.
    public var label: String { display.isEmpty ? text : display }

    /// Creates an item.
    public init(text: String, display: String = "", meta: String = "", kind: String? = nil) {
        self.text = text
        self.display = display
        self.meta = meta
        self.kind = kind
    }

    /// Decodes an item. The server may leave `display` and `meta` out.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        display = try container.decodeIfPresent(String.self, forKey: .display) ?? ""
        meta = try container.decodeIfPresent(String.self, forKey: .meta) ?? ""
        kind = try container.decodeIfPresent(String.self, forKey: .kind)
    }

    enum CodingKeys: String, CodingKey {
        case text, display, meta, kind
    }
}

/// Result of `complete.slash`.
public struct CompleteSlashResult: Sendable, Equatable, Codable {
    /// Completions, best match first.
    public var items: [CompletionItem]

    /// Decodes the result. A missing `items` list reads as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([CompletionItem].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

/// Result of `complete.path`.
public struct CompletionItemsResult: Sendable, Equatable, Codable {
    /// Completions, best match first.
    public var items: [CompletionItem]

    /// Decodes the result. A missing `items` list reads as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([CompletionItem].self, forKey: .items) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case items
    }
}

extension GatewayClient {
    /// Calls `complete.slash`.
    public func completeSlash(_ params: CompleteSlashParams) async throws -> CompleteSlashResult {
        try await call("complete.slash", params: params)
    }

    /// Calls `complete.path`.
    public func completePath(_ params: CompletePathParams) async throws -> CompletionItemsResult {
        try await call("complete.path", params: params)
    }
}
