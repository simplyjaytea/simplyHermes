import Foundation

/// Saved connections and which one is active, without secrets.
public struct SavedConnections: Sendable, Equatable, Codable {
    /// Connections in the order the user added them.
    public var connections: [ServerConnection]
    /// The connection the app uses now.
    public var activeID: UUID?

    /// Creates a value.
    public init(connections: [ServerConnection] = [], activeID: UUID? = nil) {
        self.connections = connections
        self.activeID = activeID
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

    /// Adds or replaces a connection by id. The first connection becomes active.
    public mutating func upsert(_ connection: ServerConnection) {
        if let index = connections.firstIndex(where: { $0.id == connection.id }) {
            connections[index] = connection
        } else {
            connections.append(connection)
        }
        if activeID == nil { activeID = connection.id }
    }

    /// Removes a connection. When it was active, the first remaining one becomes active.
    public mutating func remove(id: UUID) {
        connections.removeAll { $0.id == id }
        if activeID == id { activeID = connections.first?.id }
    }

    /// The active connection.
    public var active: ServerConnection? {
        connections.first { $0.id == activeID }
    }
}
