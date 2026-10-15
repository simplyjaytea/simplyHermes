import Foundation

/// Saved connections and which one is active, without secrets.
public struct SavedConnections: Sendable, Equatable, Codable {
    /// Connections in the order the user added them.
    public var connections: [ServerConnection]
    /// The connection the app uses now.
    public var activeID: UUID?
    /// The primary connection: the one opened on launch by default (WP-15). The first connection added.
    public var primaryID: UUID?
    /// The last connection that connected successfully.
    public var lastUsedID: UUID?
    /// Which connection opens after a restart.
    public var openOnLaunch: OpenOnLaunch

    /// Which connection the app opens after a restart, as in Hermes Desktop.
    public enum OpenOnLaunch: String, Sendable, Equatable, Codable, CaseIterable {
        /// The primary connection.
        case primary
        /// The last connection that connected successfully.
        case lastUsed
    }

    /// Creates a value.
    public init(
        connections: [ServerConnection] = [], activeID: UUID? = nil, primaryID: UUID? = nil,
        lastUsedID: UUID? = nil, openOnLaunch: OpenOnLaunch = .primary
    ) {
        self.connections = connections
        self.activeID = activeID
        self.primaryID = primaryID
        self.lastUsedID = lastUsedID
        self.openOnLaunch = openOnLaunch
    }

    enum CodingKeys: String, CodingKey {
        case connections, activeID, primaryID, lastUsedID, openOnLaunch
    }

    /// Reads files written before WP-15, which have no primary, last used or launch choice.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        connections = try container.decode([ServerConnection].self, forKey: .connections)
        activeID = try container.decodeIfPresent(UUID.self, forKey: .activeID)
        primaryID = try container.decodeIfPresent(UUID.self, forKey: .primaryID) ?? connections.first?.id
        lastUsedID = try container.decodeIfPresent(UUID.self, forKey: .lastUsedID)
        openOnLaunch = try container.decodeIfPresent(OpenOnLaunch.self, forKey: .openOnLaunch) ?? .primary
    }
}

/// Reads and writes ``SavedConnections`` as a JSON file. Secrets stay in the ``CredentialStore``.
///
/// GRDB replaces this file once the database lands; the shape stays the same.
public struct ConnectionStore: Sendable {
    /// The JSON file.
    public let fileURL: URL

    /// Creates a store for `fileURL`. The directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The default file in Application Support, or in the App Group container when one is given.
    public static func defaultFileURL(appGroupContainer: URL? = nil) -> URL {
        let base =
            appGroupContainer
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("simplyHermes", isDirectory: true)
            .appendingPathComponent("connections.json")
    }

    /// Loads the file. A missing file is an empty list.
    public func load() throws -> SavedConnections {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return SavedConnections() }
        return try JSONDecoder().decode(SavedConnections.self, from: Data(contentsOf: fileURL))
    }

    /// Saves atomically.
    public func save(_ saved: SavedConnections) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(saved).write(to: fileURL, options: .atomic)
    }
}

extension SavedConnections {
    /// The connection that ``ServerConnection/dedupeKey`` matches, other than `excluding`.
    public func duplicate(of connection: ServerConnection, excluding: UUID? = nil) -> ServerConnection? {
        let key = connection.dedupeKey
        return connections.first { $0.id != (excluding ?? connection.id) && $0.dedupeKey == key }
    }

    /// Adds or replaces a connection by id. The first connection becomes active and primary.
    public mutating func upsert(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if activeID == nil { activeID = connection.id }
        if primaryID == nil { primaryID = connection.id }
    }

    /// Removes a connection. When it was active or primary, the first remaining one takes its place.
    public mutating func remove(id: UUID) {
        connections.removeAll { $0.id == id }
        if activeID == id { activeID = connections.first?.id }
        if primaryID == id { primaryID = connections.first?.id }
        if lastUsedID == id { lastUsedID = nil }
    }

    /// The active connection.
    public var active: ServerConnection? {
        connections.first { $0.id == activeID }
    }
}
