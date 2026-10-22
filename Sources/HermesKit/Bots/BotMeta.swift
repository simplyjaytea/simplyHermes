import Foundation

/// The `ui_meta` namespaces a bot carries. The server replaces a whole namespace on write, so every write is a
/// read-modify-write of that namespace object (plan 2.5, WP-42).
public enum BotMetaNamespace {
    /// Hermes Desktop's Bot Mode namespace: title, pinned, hidden, created, sections and groups.
    public static let desktop = "hermes-bots"
    /// This app's own namespace: the monogram, emoji or symbol avatar. Hermes Desktop never reads it.
    public static let app = "simplyhermes"
    /// Largest `ui_meta` payload the server accepts (`tui_gateway/methods_profiles.py`, 64 KB of JSON).
    public static let maxPayloadBytes = 65_536
}

/// One namespace object. Keys this client does not model stay as they are, so a write never drops them.
public struct BotMetaObject: Sendable, Equatable {
    public private(set) var values: [String: JSONValue]

    public init(values: [String: JSONValue] = [:]) {
        self.values = values
    }

    /// Reads a namespace value; a missing or non-object value starts empty.
    public init(_ value: JSONValue?) {
        self.values = value?.objectValue ?? [:]
    }

    /// The bot's title. Empty or missing means no title.
    public var title: String? {
        get { BotNaming.nonEmpty(values["title"]?.stringValue) }
        set { setValue("title", BotNaming.nonEmpty(newValue).map { JSONValue.string($0) }) }
    }

    public var pinned: Bool {
        get { values["pinned"]?.boolValue ?? false }
        set { setValue("pinned", .bool(newValue)) }
    }

    public var hidden: Bool {
        get { values["hidden"]?.boolValue ?? false }
        set { setValue("hidden", .bool(newValue)) }
    }

    /// Creation time in milliseconds since the Unix epoch.
    public var createdAt: Int? {
        get { values["created"]?.intValue }
        set { setValue("created", newValue.map { JSONValue.int($0) }) }
    }

    /// Room memberships. Reads `groups` when it is an array, else the single `group`; writing keeps `group` as the first.
    public var groups: [String] {
        get {
            if let array = values["groups"]?.arrayValue {
                return Self.uniqueNames(array.compactMap(\.stringValue))
            }
            return Self.uniqueNames([values["group"]?.stringValue].compactMap { $0 })
        }
        set {
            let names = Self.uniqueNames(newValue)
            setValue("groups", names.isEmpty ? nil : .array(names.map { JSONValue.string($0) }))
            setValue("group", names.first.map { JSONValue.string($0) })
        }
    }

    /// Lets Desktop show the bot in its own section list. Only the id and name travel with the bot.
    public var sectionID: String? {
        get { BotNaming.nonEmpty(values["sectionId"]?.stringValue) }
        set { setValue("sectionId", BotNaming.nonEmpty(newValue).map { JSONValue.string($0) }) }
    }

    public var sectionName: String? {
        get { BotNaming.nonEmpty(values["sectionName"]?.stringValue) }
        set { setValue("sectionName", BotNaming.nonEmpty(newValue).map { JSONValue.string($0) }) }
    }

    /// The object to write back. Desktop's `chat` key is stripped on every write, as Desktop does.
    public var writable: JSONValue {
        var copy = values
        copy["chat"] = nil
        return .object(copy)
    }

    /// Sets or, with nil, removes a key.
    public mutating func setValue(_ key: String, _ value: JSONValue?) {
        values[key] = value
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for name in names.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
            if seen.insert(name).inserted { result.append(name) }
        }
        return result
    }
}

/// The avatar this app shows: monogram, emoji or SF Symbol (plan Q33). Stored in `ui_meta["simplyhermes"]`.
public struct BotAppLook: Sendable, Equatable {
    public var avatar: BotAvatar?

    public init(avatar: BotAvatar?) {
        self.avatar = avatar
    }

    public init(object: BotMetaObject) {
        self.avatar = object.values["avatar"].flatMap(BotAvatar.init(json:))
    }

    /// The namespace object with this look applied. Other keys in the object are kept.
    public func applied(to object: BotMetaObject) -> BotMetaObject {
        var copy = object
        copy.setValue("avatar", avatar?.json)
        copy.setValue("version", .int(1))
        return copy
    }
}

/// A namespace value ready for `profiles.configure`, with the revision it must still have.
public struct BotMetaWrite: Sendable, Equatable {
    public var namespace: String
    public var value: JSONValue
    /// The revision the server must still report. Nil means no compare-and-swap (an older gateway).
    public var expectedRevision: Int?

    public init(namespace: String, value: JSONValue, expectedRevision: Int?) {
        self.namespace = namespace
        self.value = value
        self.expectedRevision = expectedRevision
    }

    /// The `ui_meta` object for a write, and its expected revisions.
    public static func payload(_ writes: [BotMetaWrite]) -> (uiMeta: JSONValue, expected: [String: Int]?) {
        let uiMeta = JSONValue.object(Dictionary(uniqueKeysWithValues: writes.map { ($0.namespace, $0.value) }))
        let pairs = writes.compactMap { write in write.expectedRevision.map { (write.namespace, $0) } }
        let expected = pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
        return (uiMeta, expected)
    }
}
