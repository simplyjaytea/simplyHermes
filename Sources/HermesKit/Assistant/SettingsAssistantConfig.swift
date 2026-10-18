import Foundation

/// The config document of `GET /api/config`. The schema gives the document as any object, so its keys are not modelled
/// here. ``RESTClient/editAssistantConfig(_:)`` writes every key back, which keeps each key a change does not name.
public struct SettingsAssistantConfig: Sendable, Equatable {
    /// The top-level keys, exactly as the server sent them.
    public private(set) var values: [String: JSONValue]

    /// The whole document as one JSON object: the `config` of `PUT /api/config`.
    public var document: JSONValue { .object(values) }

    /// Wraps the answer of `GET /api/config`. Throws ``SettingsAssistantConfigError`` when it is not a JSON object.
    public init(answer: JSONValue) throws {
        guard let object = answer.objectValue else { throw SettingsAssistantConfigError.notAnObject(path: []) }
        values = object
    }

    /// A document with these keys. For tests and previews.
    public init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    /// The value at `path`, for example `["voice", "enabled"]`. Nil when a key on the way is missing.
    public func value(at path: [String]) -> JSONValue? {
        var current = JSONValue.object(values)
        for key in path {
            guard let next = current[key] else { return nil }
            current = next
        }
        return current
    }

    /// Sets the value at `path`, creating objects for missing keys. A `null` on the way counts as missing. Throws when
    /// a key on the way holds a number, string, boolean or array, so nothing is replaced by accident.
    public mutating func set(_ value: JSONValue, at path: [String]) throws {
        guard let key = path.first else { throw SettingsAssistantConfigError.emptyPath }
        values[key] = try Self.updated(values[key], path: path.dropFirst(), value: value, location: [key])
    }

    /// The node at `location` after `value` is stored at the end of `path`.
    private static func updated(
        _ node: JSONValue?, path: ArraySlice<String>, value: JSONValue, location: [String]
    ) throws -> JSONValue {
        guard let key = path.first else { return value }
        var object: [String: JSONValue]
        switch node {
        case nil, .null?:
            object = [:]
        case .object(let existing)?:
            object = existing
        default:
            throw SettingsAssistantConfigError.notAnObject(path: location)
        }
        object[key] = try updated(
            object[key], path: path.dropFirst(), value: value, location: location + [key])
        return .object(object)
    }
}

/// Why a config document could not be read or changed. Nothing is written when one of these is thrown.
public enum SettingsAssistantConfigError: Error, Sendable, Equatable {
    /// The answer, or the value at `path`, is not a JSON object.
    case notAnObject(path: [String])
    /// ``SettingsAssistantConfig/set(_:at:)`` got an empty path.
    case emptyPath
}
