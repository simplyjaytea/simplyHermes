/// A string-valued enum that keeps values it does not know, so a new server value never fails a decode.
///
/// Conforming types provide `init(wire:)` and `wire`. Each has an `unknown(String)` case for unrecognised values.
public protocol HermesStringEnum: Sendable, Hashable, Codable {
    /// Creates the case for a wire string. A string with no known case becomes `unknown`.
    init(wire: String)
    /// The wire string.
    var wire: String { get }
}

extension HermesStringEnum {
    /// Decodes the wire string.
    public init(from decoder: any Decoder) throws {
        self.init(wire: try decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the wire string.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wire)
    }
}

/// Answer to an `approval` request. `unknown` keeps choices added by a newer server.
public enum ApprovalChoice: HermesStringEnum {
    /// Allow this one command.
    case once
    /// Allow for this session.
    case session
    /// Allow permanently.
    case always
    /// Refuse.
    case deny
    /// A choice this client does not know.
    case unknown(String)

    /// Creates the choice for a wire string.
    public init(wire: String) {
        switch wire {
        case "once": self = .once
        case "session": self = .session
        case "always": self = .always
        case "deny": self = .deny
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .once: "once"
        case .session: "session"
        case .always: "always"
        case .deny: "deny"
        case .unknown(let value): value
        }
    }
}

/// Final status of an assistant turn, from `message.complete`.
public enum TurnStatus: HermesStringEnum {
    /// The turn finished.
    case complete
    /// The turn ended in an error.
    case error
    /// The turn was interrupted; the text is partial.
    case interrupted
    /// A status this client does not know.
    case unknown(String)

    /// Creates the status for a wire string.
    public init(wire: String) {
        switch wire {
        case "complete": self = .complete
        case "error": self = .error
        case "interrupted": self = .interrupted
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .complete: "complete"
        case .error: "error"
        case .interrupted: "interrupted"
        case .unknown(let value): value
        }
    }
}

/// Result of `prompt.submit`. `steered` and `redirected` mean a prompt changed a running turn.
public enum PromptSubmitStatus: HermesStringEnum {
    /// The turn started.
    case streaming
    /// The session was busy; the prompt was queued server-side.
    case queued
    /// The prompt steered a running turn.
    case steered
    /// The prompt redirected a running turn.
    case redirected
    /// A status this client does not know.
    case unknown(String)

    /// Creates the status for a wire string.
    public init(wire: String) {
        switch wire {
        case "streaming": self = .streaming
        case "queued": self = .queued
        case "steered": self = .steered
        case "redirected": self = .redirected
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .streaming: "streaming"
        case .queued: "queued"
        case .steered: "steered"
        case .redirected: "redirected"
        case .unknown(let value): value
        }
    }
}

/// Result of `session.interrupt`.
public enum InterruptStatus: HermesStringEnum {
    /// A running turn was interrupted.
    case interrupted
    /// There was no running turn.
    case notInterrupted
    /// A status this client does not know.
    case unknown(String)

    /// Creates the status for a wire string.
    public init(wire: String) {
        switch wire {
        case "interrupted": self = .interrupted
        case "not_interrupted": self = .notInterrupted
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .interrupted: "interrupted"
        case .notInterrupted: "not_interrupted"
        case .unknown(let value): value
        }
    }
}

/// Lifecycle of one delegated child agent.
public enum SubagentStatus: HermesStringEnum {
    /// Waiting to start.
    case queued
    /// Running.
    case running
    /// Finished successfully (terminal).
    case completed
    /// Finished with a failure (terminal).
    case failed
    /// Finished with an error (terminal).
    case error
    /// Timed out (terminal).
    case timeout
    /// Interrupted (terminal).
    case interrupted
    /// A status this client does not know.
    case unknown(String)

    /// Creates the status for a wire string.
    public init(wire: String) {
        switch wire {
        case "queued": self = .queued
        case "running": self = .running
        case "completed": self = .completed
        case "failed": self = .failed
        case "error": self = .error
        case "timeout": self = .timeout
        case "interrupted": self = .interrupted
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .queued: "queued"
        case .running: "running"
        case .completed: "completed"
        case .failed: "failed"
        case .error: "error"
        case .timeout: "timeout"
        case .interrupted: "interrupted"
        case .unknown(let value): value
        }
    }
}

/// Live state of a session in `session.active_list`, `session.resume` and `session.activate`.
public enum LiveSessionStatus: HermesStringEnum {
    /// No turn is running.
    case idle
    /// The session is starting.
    case starting
    /// Waiting on the user, for example an approval.
    case waiting
    /// A turn is running.
    case working
    /// A turn is streaming text.
    case streaming
    /// The session is being re-attached.
    case resuming
    /// A status this client does not know.
    case unknown(String)

    /// Creates the status for a wire string.
    public init(wire: String) {
        switch wire {
        case "idle": self = .idle
        case "starting": self = .starting
        case "waiting": self = .waiting
        case "working": self = .working
        case "streaming": self = .streaming
        case "resuming": self = .resuming
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .idle: "idle"
        case .starting: "starting"
        case .waiting: "waiting"
        case .working: "working"
        case .streaming: "streaming"
        case .resuming: "resuming"
        case .unknown(let value): value
        }
    }
}

/// Which surface a tool label runs on.
public enum ToolLabelKind: HermesStringEnum {
    /// A connector.
    case connector
    /// An MCP server tool.
    case mcp
    /// A plain tool.
    case tool
    /// A kind this client does not know.
    case unknown(String)

    /// Creates the kind for a wire string.
    public init(wire: String) {
        switch wire {
        case "connector": self = .connector
        case "mcp": self = .mcp
        case "tool": self = .tool
        default: self = .unknown(wire)
        }
    }

    /// The wire string.
    public var wire: String {
        switch self {
        case .connector: "connector"
        case .mcp: "mcp"
        case .tool: "tool"
        case .unknown(let value): value
        }
    }
}
