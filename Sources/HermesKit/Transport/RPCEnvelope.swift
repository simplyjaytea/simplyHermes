import Foundation

/// A JSON-RPC 2.0 request id: a string or an integer. The client uses strings.
public enum RPCID: Sendable, Hashable, Codable, CustomStringConvertible {
    /// A string id, such as `"A1"` or `"srq-bb333022bf70"`.
    case string(String)
    /// An integer id.
    case int(Int)

    /// Decodes a string or an integer id.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .int(try container.decode(Int.self))
        }
    }

    /// Encodes the id as a JSON string or integer.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        }
    }

    /// The id as text.
    public var description: String {
        switch self {
        case .string(let value): value
        case .int(let value): String(value)
        }
    }
}

extension RPCID: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    /// String literals become `.string`.
    public init(stringLiteral value: String) {
        self = .string(value)
    }

    /// Integer literals become `.int`.
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

/// A JSON-RPC request the client sends, or a server-to-client request it receives.
public struct RPCRequest: Sendable, Hashable, Codable {
    /// The request id. The server answers with a response carrying the same id.
    public var id: RPCID
    /// The method name, such as `session.create`.
    public var method: String
    /// The params object. Nil means the key is omitted.
    public var params: JSONValue?

    /// Creates a request with raw params.
    public init(id: RPCID, method: String, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    /// Creates a request whose params come from a typed value. Absent optionals are omitted from the JSON.
    public init<Params: Encodable>(id: RPCID, method: String, params: Params) throws {
        self.id = id
        self.method = method
        self.params = try JSONValue(encoding: params)
    }

    /// Decodes the params as `Params`. A missing params key decodes as an empty object.
    public func decodeParams<Params: Decodable>(_ type: Params.Type = Params.self) throws -> Params {
        try (params ?? .object([:])).decode(type)
    }

    /// Decodes `{"jsonrpc","id","method","params"}`. Unknown keys are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RPCWireKey.self)
        id = try container.decode(RPCID.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    /// Encodes `{"jsonrpc":"2.0","id","method","params"}`. The params key is omitted when nil.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RPCWireKey.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

/// A JSON-RPC notification: a method call with no id. Events use the method `event`.
public struct RPCNotification: Sendable, Hashable, Codable {
    /// The method name.
    public var method: String
    /// The params object, when present.
    public var params: JSONValue?

    /// Creates a notification.
    public init(method: String, params: JSONValue? = nil) {
        self.method = method
        self.params = params
    }

    /// Decodes `{"jsonrpc","method","params"}`. Unknown keys are ignored.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RPCWireKey.self)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    /// Encodes `{"jsonrpc":"2.0","method","params"}`. The params key is omitted when nil.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RPCWireKey.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

/// A JSON-RPC error object.
public struct RPCError: Error, Sendable, Hashable, Codable {
    /// The error code. Application codes are in ``HermesErrorCode``.
    public var code: Int
    /// A human-readable message.
    public var message: String
    /// Optional structured detail, such as the `data` of a 4018 error.
    public var data: JSONValue?

    /// Creates an error object.
    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// A JSON-RPC response: the answer to a request, with either a result or an error.
public struct RPCResponse: Sendable, Hashable, Codable {
    /// The id of the request being answered. Nil only for a parse error (`-32700`).
    public var id: RPCID?
    /// The result or the error.
    public var outcome: Outcome

    /// Either a result (which may be `null`) or an error.
    public enum Outcome: Sendable, Hashable {
        /// A successful result.
        case result(JSONValue)
        /// A failure.
        case error(RPCError)
    }

    /// Creates a successful response.
    public init(id: RPCID?, result: JSONValue) {
        self.id = id
        self.outcome = .result(result)
    }

    /// Creates an error response.
    public init(id: RPCID?, error: RPCError) {
        self.id = id
        self.outcome = .error(error)
    }

    /// The response for an unimplemented server request: `-32601`, so the agent fails fast.
    public static func methodNotFound(id: RPCID, method: String) -> RPCResponse {
        RPCResponse(id: id, error: RPCError(code: HermesErrorCode.methodNotFound, message: "unknown method: \(method)"))
    }

    /// The result, when the response succeeded.
    public var result: JSONValue? {
        guard case .result(let value) = outcome else { return nil }
        return value
    }

    /// The error, when the response failed.
    public var error: RPCError? {
        guard case .error(let value) = outcome else { return nil }
        return value
    }

    /// Decodes the result as `Value`. Returns nil for an error response.
    public func decodeResult<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value? {
        guard let result else { return nil }
        return try result.decode(type)
    }

    /// Decodes `{"jsonrpc","id","result"|"error"}`. Throws when neither result nor error is present.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RPCWireKey.self)
        self = try RPCResponse.decodeFields(from: container)
    }

    /// Encodes `{"jsonrpc":"2.0","id","result"|"error"}`. A nil id is written as `null`.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: RPCWireKey.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        switch outcome {
        case .result(let value): try container.encode(value, forKey: .result)
        case .error(let error): try container.encode(error, forKey: .error)
        }
    }

    /// Shared with ``RPCFrame``, which reads the same keys from one container.
    static func decodeFields(from container: KeyedDecodingContainer<RPCWireKey>) throws -> RPCResponse {
        let id = try container.decodeIfPresent(RPCID.self, forKey: .id)
        if let error = try container.decodeIfPresent(RPCError.self, forKey: .error) {
            return RPCResponse(id: id, error: error)
        }
        guard container.contains(.result) else {
            throw DecodingError.dataCorruptedError(
                forKey: .result, in: container, debugDescription: "response has neither result nor error")
        }
        return RPCResponse(id: id, result: try container.decode(JSONValue.self, forKey: .result))
    }
}

/// One JSON-RPC frame from the server, classified.
///
/// Requests (method and id) include server-to-client requests such as `approval`. `event` notifications decode to
/// ``GatewayEventEnvelope``. Frames that are not valid JSON-RPC throw.
public enum RPCFrame: Sendable, Equatable, Decodable, Encodable {
    /// A request: the client's own call echoed back, or a server-to-client request.
    case request(RPCRequest)
    /// A response to a request the client sent.
    case response(RPCResponse)
    /// A gateway event (`method` is `event`).
    case event(GatewayEventEnvelope)
    /// Any other notification (a method with no id).
    case notification(RPCNotification)

    /// Classifies and decodes a frame. Throws for input that is not a JSON-RPC message.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: RPCWireKey.self)
        let id = try container.decodeIfPresent(RPCID.self, forKey: .id)
        guard let method = try container.decodeIfPresent(String.self, forKey: .method) else {
            self = .response(try RPCResponse.decodeFields(from: container))
            return
        }
        guard let id else {
            if method == GatewayEventEnvelope.method {
                self = .event(try GatewayEventEnvelope(from: container.superDecoder(forKey: .params)))
            } else {
                self = .notification(
                    RPCNotification(
                        method: method, params: try container.decodeIfPresent(JSONValue.self, forKey: .params)))
            }
            return
        }
        self = .request(
            RPCRequest(id: id, method: method, params: try container.decodeIfPresent(JSONValue.self, forKey: .params)))
    }

    /// Encodes the frame in its JSON-RPC shape.
    public func encode(to encoder: any Encoder) throws {
        switch self {
        case .request(let request):
            try request.encode(to: encoder)
        case .response(let response):
            try response.encode(to: encoder)
        case .event(let envelope):
            var container = encoder.container(keyedBy: RPCWireKey.self)
            try container.encode("2.0", forKey: .jsonrpc)
            try container.encode(GatewayEventEnvelope.method, forKey: .method)
            try container.encode(envelope, forKey: .params)
        case .notification(let notification):
            try notification.encode(to: encoder)
        }
    }
}

/// The wire keys of a JSON-RPC message. Shared by ``RPCRequest``, ``RPCResponse`` and ``RPCFrame``.
enum RPCWireKey: String, CodingKey {
    case jsonrpc, id, method, params, result, error
}
