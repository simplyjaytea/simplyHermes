/// The directive kinds `command.dispatch` answers with.
public enum DispatchType: String, Sendable, Equatable, Codable {
    /// A shell command. Its result is in `output`.
    case exec
    /// Another command to run in place of this one. Its name is in `target`.
    case alias
    /// A plugin command. Its result is in `output`.
    case plugin
    /// A prompt for the model. Its text is in `message`.
    case send
    /// A skill. Its prompt is in `message`.
    case skill
    /// Text for the composer, not sent. Its text is in `message`.
    case prefill
}

/// Params of `command.dispatch`: runs one slash command on the server.
public struct CommandDispatchParams: Sendable, Equatable, Codable {
    /// The command name, without the slash.
    public var name: String
    /// The text after the name. Nil when there is none.
    public var arg: String?
    /// Session the command runs in.
    public var sessionID: String?
    /// Profile to scope the call to.
    public var profile: String?

    /// Creates the params.
    public init(name: String, arg: String? = nil, sessionID: String? = nil, profile: String? = nil) {
        self.name = name
        self.arg = arg
        self.sessionID = sessionID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case name, arg, profile
        case sessionID = "session_id"
    }
}

/// Result of `command.dispatch`: one directive. `exec` and `plugin` carry `output`, `alias` a `target`, and `send`,
/// `prefill` and `skill` a `message`. The UI renders `display`, never `message`.
public struct CommandDispatchResult: Sendable, Equatable, Codable {
    /// Which directive this is.
    public var type: DispatchType
    /// What the command printed (`exec`, `plugin`).
    public var output: String?
    /// The command to run instead (`alias`).
    public var target: String?
    /// The text the directive carries (`send`, `skill`, `prefill`).
    public var message: String?
    /// What the UI shows in place of `message`.
    public var display: String?
    /// A short note from the server.
    public var notice: String?
}
