/// Params of the server request `approval`: a dangerous command awaits the user's decision.
///
/// Answer with ``ApprovalAnswer`` as the result of the request, or with `approval.respond` from any socket.
public struct ApprovalRequest: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Id of the approval, used by `approval.respond`.
    public var requestID: String
    /// The command that needs approval.
    public var command: String?
    /// Why it needs approval.
    public var description: String?
    /// Pattern that matched the command.
    public var patternKey: String?
    /// Patterns that matched the command.
    public var patternKeys: [String]?
    /// Whether "always" is offered.
    public var allowPermanent: Bool?
    /// Whether "session" is offered.
    public var allowSession: Bool?
    /// True when smart approval denied the command outright.
    public var smartDenied: Bool?
    /// Choices offered. Unknown choices are kept as ``ApprovalChoice/unknown(_:)``.
    public var choices: [ApprovalChoice]?
    /// The tool that asked for approval.
    public var toolName: String?
    /// The gateway session id, when the request came through a gateway.
    public var gatewaySessionID: String?

    enum CodingKeys: String, CodingKey {
        case command, description, choices
        case sessionID = "session_id"
        case requestID = "request_id"
        case patternKey = "pattern_key"
        case patternKeys = "pattern_keys"
        case allowPermanent = "allow_permanent"
        case allowSession = "allow_session"
        case smartDenied = "smart_denied"
        case toolName = "tool_name"
        case gatewaySessionID = "gateway_session_id"
    }
}

/// Result of an `approval` request: the user's choice.
public struct ApprovalAnswer: Sendable, Equatable, Codable {
    /// The choice.
    public var choice: ApprovalChoice
    /// Apply the choice to every pending approval, when set.
    public var all: Bool?

    /// Creates an answer.
    public init(choice: ApprovalChoice, all: Bool? = nil) {
        self.choice = choice
        self.all = all
    }
}

/// Params of the server request `clarify`: the agent asks the user one to five questions.
public struct ClarifyRequest: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// The questions, in order.
    public var questions: [ClarifyQuestion]
    /// Answers the server already has, keyed by question id. A nil value is an unanswered question.
    public var answers: [String: String?]?

    enum CodingKeys: String, CodingKey {
        case questions, answers
        case sessionID = "session_id"
    }
}

/// One question of a `clarify` request.
public struct ClarifyQuestion: Sendable, Equatable, Codable {
    /// Question id. The answer is keyed by it.
    public var qid: String
    /// The question text.
    public var question: String
    /// Choices to offer. Nil for a free-text question. The first choice may carry "(Recommended)".
    public var choices: [String]?
    /// True when more than one choice may be picked.
    public var multiSelect: Bool

    /// Creates a question.
    public init(qid: String, question: String, choices: [String]? = nil, multiSelect: Bool = false) {
        self.qid = qid
        self.question = question
        self.choices = choices
        self.multiSelect = multiSelect
    }

    /// Decodes a question. `multi_select` defaults to false when absent.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        qid = try container.decode(String.self, forKey: .qid)
        question = try container.decode(String.self, forKey: .question)
        choices = try container.decodeIfPresent([String].self, forKey: .choices)
        multiSelect = try container.decodeIfPresent(Bool.self, forKey: .multiSelect) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case qid, question, choices
        case multiSelect = "multi_select"
    }
}

/// Result of a `clarify` request: the answer to each question, keyed by question id.
public struct ClarifyAnswer: Sendable, Equatable, Codable {
    /// Answer text by question id.
    public var answers: [String: String]

    /// Creates an answer.
    public init(answers: [String: String]) {
        self.answers = answers
    }
}

/// Params of the server request `sudo`: the terminal tool needs a password.
public struct SudoRequest: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// The command that needs sudo.
    public var command: String?

    enum CodingKeys: String, CodingKey {
        case command
        case sessionID = "session_id"
    }
}

/// Params of the server request `secret`: a skill or setup flow asks for a named environment variable.
public struct SecretRequest: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Environment variable the value is for.
    public var envVar: String
    /// Prompt to show the user.
    public var prompt: String
    /// Extra metadata. Kept raw.
    public var metadata: JSONValue?

    enum CodingKeys: String, CodingKey {
        case prompt, metadata
        case sessionID = "session_id"
        case envVar = "env_var"
    }
}

/// Result of the `sudo` and `secret` requests: the masked value the user typed.
///
/// Printing, logging or dumping an answer never shows the value.
public struct ValueAnswer: Sendable, Equatable, Codable, CustomStringConvertible, CustomDebugStringConvertible,
    CustomReflectable
{
    /// The value.
    public var value: String

    /// Creates an answer.
    public init(value: String) {
        self.value = value
    }

    /// A fixed text without the value.
    public var description: String { "ValueAnswer(<redacted>)" }

    /// A fixed text without the value.
    public var debugDescription: String { description }

    /// No children, so `dump` and `Mirror` show nothing.
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// A server-to-client request, typed by its method.
///
/// Decode one from an ``RPCFrame`` with ``init(frame:)``. Answer with the matching answer type, or with
/// ``RPCResponse/methodNotFound(id:method:)`` for ``unknown(id:method:params:)``.
public enum ServerRequest: Sendable, Equatable {
    /// `approval`: a command needs the user's decision.
    case approval(id: RPCID, ApprovalRequest)
    /// `clarify`: the agent asks the user questions.
    case clarify(id: RPCID, ClarifyRequest)
    /// `sudo`: a password is needed.
    case sudo(id: RPCID, SudoRequest)
    /// `secret`: a named environment variable is needed.
    case secret(id: RPCID, SecretRequest)
    /// A method this client does not model. Answer `-32601`.
    case unknown(id: RPCID, method: String, params: JSONValue?)

    /// The JSON-RPC id the answer must carry.
    public var id: RPCID {
        switch self {
        case .approval(let id, _), .clarify(let id, _), .sudo(let id, _), .secret(let id, _): id
        case .unknown(let id, _, _): id
        }
    }

    /// Builds a server request from a frame. Returns nil for frames that are not requests.
    ///
    /// Throws when the params of a known method do not decode. Answer such a request with `-32603`.
    public init?(frame: RPCFrame) throws {
        guard case .request(let request) = frame else { return nil }
        try self.init(request: request)
    }

    /// Builds a server request from a request. Throws when the params of a known method do not decode.
    public init(request: RPCRequest) throws {
        switch request.method {
        case "approval":
            self = .approval(id: request.id, try request.decodeParams(ApprovalRequest.self))
        case "clarify":
            self = .clarify(id: request.id, try request.decodeParams(ClarifyRequest.self))
        case "sudo":
            self = .sudo(id: request.id, try request.decodeParams(SudoRequest.self))
        case "secret":
            self = .secret(id: request.id, try request.decodeParams(SecretRequest.self))
        default:
            self = .unknown(id: request.id, method: request.method, params: request.params)
        }
    }
}
