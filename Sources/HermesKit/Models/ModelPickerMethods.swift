/// Params of `config.set`. `value` is the raw text the setter normalises, such as a model name or a reasoning level.
public struct ConfigSetParams: Sendable, Equatable, Codable {
    /// Config key, such as `model` or `reasoning`.
    public var key: String
    /// New value, as the user would type it.
    public var value: String
    /// Session the change applies to.
    public var sessionID: String?
    /// Where the change lands, for keys that take a scope such as `reasoning`. `session` limits it to this session.
    public var scope: String?
    /// True to switch to a model the server flagged as expensive.
    public var confirmExpensiveModel: Bool

    /// Creates the params.
    public init(
        key: String, value: String, sessionID: String? = nil, scope: String? = nil,
        confirmExpensiveModel: Bool = false
    ) {
        self.key = key
        self.value = value
        self.sessionID = sessionID
        self.scope = scope
        self.confirmExpensiveModel = confirmExpensiveModel
    }

    enum CodingKeys: String, CodingKey {
        case key, value, scope
        case sessionID = "session_id"
        case confirmExpensiveModel = "confirm_expensive_model"
    }
}

/// Result of `config.set`: the stored value, plus what a model switch needs the user to know.
public struct ConfigSetResult: Sendable, Equatable, Codable {
    /// The key that was set.
    public var key: String
    /// The value the server stored. A bool for the display toggles.
    public var value: JSONValue?
    /// Text to show about the change, such as a model that lacks a feature.
    public var warning: String?
    /// True when the server holds the switch until the user confirms.
    public var confirmRequired: Bool?
    /// Text to show with the confirmation.
    public var confirmMessage: String?
    /// Where the change landed.
    public var scope: String?
    /// True when the change takes effect on the next turn.
    public var deferred: Bool?

    /// What the change did. A pending confirmation comes before a warning.
    public var outcome: ModelSwitchOutcome {
        guard confirmRequired == true else { return .applied(warning: warning) }
        return .needsConfirmation(message: confirmMessage ?? "Confirm to switch to this model.")
    }

    enum CodingKeys: String, CodingKey {
        case key, value, warning, scope, deferred
        case confirmRequired = "confirm_required"
        case confirmMessage = "confirm_message"
    }
}

/// What a model switch did. The server can hold an expensive model until the user confirms.
public enum ModelSwitchOutcome: Sendable, Equatable {
    /// The switch took effect. `warning` is text to show, when the server sent one.
    case applied(warning: String?)
    /// The switch waits. Send the same change again with `confirmExpensiveModel` set.
    case needsConfirmation(message: String)
}

extension GatewayClient {
    /// Calls `config.set`.
    public func configSet(_ params: ConfigSetParams) async throws -> ConfigSetResult {
        try await call("config.set", params: params)
    }

    /// Calls `model.options`: the providers and models the picker lists, layered over the session's live provider.
    public func modelOptions(_ params: ModelOptionsParams) async throws -> ModelOptionsResult {
        try await call("model.options", params: params)
    }
}
