import Foundation

/// What the Home and Lock Screen widgets show: bots, who is working, and approvals waiting.
///
/// The app writes it to the shared container when something a widget shows changes (a turn starts or
/// ends, an approval arrives or is answered), never on every streamed token. Widgets only read it.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct Bot: Codable, Hashable, Sendable, Identifiable {
        public var id: String
        public var name: String
        public var isActive: Bool
        /// "Running tests", "Idle", "Waiting for you".
        public var statusLine: String

        public init(id: String, name: String, isActive: Bool, statusLine: String) {
            self.id = id
            self.name = name
            self.isActive = isActive
            self.statusLine = statusLine
        }
    }

    public struct Approval: Codable, Hashable, Sendable, Identifiable {
        public var sessionID: String
        public var botName: String
        public var command: String

        public var id: String { sessionID }

        public init(sessionID: String, botName: String, command: String) {
            self.sessionID = sessionID
            self.botName = botName
            self.command = LiveTurnState.cut(command, to: LiveTurnState.commandLimit)
        }
    }

    /// After this long without a write, widgets say "Updated … ago" in a warning color.
    public static let staleAfter: TimeInterval = 10 * 60

    public var bots: [Bot]
    public var approvals: [Approval]
    public var updatedAt: Date

    public init(bots: [Bot], approvals: [Approval], updatedAt: Date) {
        self.bots = bots
        self.approvals = approvals
        self.updatedAt = updatedAt
    }

    public var activeBotCount: Int { bots.filter(\.isActive).count }

    public func isStale(at now: Date) -> Bool {
        now.timeIntervalSince(updatedAt) > Self.staleAfter
    }

    /// Same content, ignoring `updatedAt`; used to skip writes and widget reloads that change nothing.
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        bots == other.bots && approvals == other.approvals
    }
}

/// Reads and writes the widget snapshot as one JSON file in the shared container.
public struct WidgetSnapshotStore: Sendable {
    public static let fileName = "widget-snapshot.json"

    public let fileURL: URL

    public init(directory: URL) {
        fileURL = directory.appendingPathComponent(Self.fileName)
    }

    public func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? Self.decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func save(_ snapshot: WidgetSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(snapshot).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
