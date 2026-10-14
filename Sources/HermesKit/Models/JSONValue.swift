import Foundation

/// Any JSON value. Used for free-form payload parts that the client does not model field by field.
///
/// Whole-number doubles are written as integers by `JSONEncoder`, so `.double(1.0)` decodes back as `.int(1)`.
public enum JSONValue: Sendable, Hashable, Codable {
    /// JSON `null`.
    case null
    /// JSON `true` or `false`.
    case bool(Bool)
    /// A JSON number that fits in `Int`.
    case int(Int)
    /// A JSON number with a fraction or exponent, or too large for `Int`.
    case double(Double)
    /// A JSON string.
    case string(String)
    /// A JSON array.
    case array([JSONValue])
    /// A JSON object.
    case object([String: JSONValue])

    /// Decodes any JSON value.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    /// Encodes this value as plain JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Converts a typed value into a JSON value, for example typed request params.
    public init<Value: Encodable>(encoding value: Value) throws {
        let data = try JSONEncoder().encode(value)
        self = try JSONDecoder().decode(JSONValue.self, from: data)
    }

    /// Decodes this value into a typed value.
    public func decode<Value: Decodable>(_ type: Value.Type = Value.self) throws -> Value {
        let data = try JSONEncoder().encode(self)
        return try JSONDecoder().decode(Value.self, from: data)
    }

    /// The string, when this value is a JSON string.
    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    /// The integer, when this value is a JSON integer.
    public var intValue: Int? {
        guard case .int(let value) = self else { return nil }
        return value
    }

    /// The number, when this value is a JSON number of any kind.
    public var doubleValue: Double? {
        switch self {
        case .int(let value): Double(value)
        case .double(let value): value
        default: nil
        }
    }

    /// The boolean, when this value is a JSON boolean.
    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    /// The elements, when this value is a JSON array.
    public var arrayValue: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    /// The members, when this value is a JSON object.
    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    /// The member for `key`, when this value is a JSON object.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        return object[key]
    }

    /// The element at `index`, when this value is a JSON array and the index is in range.
    public subscript(index: Int) -> JSONValue? {
        guard case .array(let array) = self, array.indices.contains(index) else { return nil }
        return array[index]
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    /// `nil` literals become `.null`.
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    /// Boolean literals become `.bool`.
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    /// Integer literals become `.int`.
    public init(integerLiteral value: Int) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    /// Float literals become `.double`.
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    /// String literals become `.string`.
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    /// Array literals become `.array`.
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    /// Dictionary literals become `.object`. A repeated key keeps its last value.
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
}
