import Foundation

/// The facts Bot settings shows for one bot, read from a `profiles.list` row (WP-41). Editing belongs to later work.
public struct BotFacts: Sendable, Equatable, Identifiable {
    /// Profile name. The id on the server.
    public var name: String
    /// The name to show: the display name when there is one, else the profile name.
    public var title: String
    /// The model pinned for the bot, when it has one.
    public var model: String?
    /// The provider of that model, when it has one.
    public var provider: String?
    /// Installed skills.
    public var skillCount: Int
    /// The bot's newest session, when the server sent one.
    public var lastSession: LastSession?
    /// Identity for lists.
    public var id: String { name }

    /// The newest session of a bot.
    public struct LastSession: Sendable, Equatable {
        /// The session's title, else the start of its first message. Empty when the session has neither.
        public var title: String
        /// When the session was last active.
        public var lastActive: Date?
        /// Messages in the session.
        public var messageCount: Int

        /// Creates a session summary.
        public init(title: String, lastActive: Date?, messageCount: Int) {
            self.title = title
            self.lastActive = lastActive
            self.messageCount = messageCount
        }
    }

    /// Creates the facts from a row. Empty strings count as missing.
    public init(row: ProfileRow) {
        name = row.name
        title = Self.text(row.displayName) ?? row.name
        model = Self.text(row.model)
        provider = Self.text(row.provider)
        skillCount = row.skillCount ?? 0
        lastSession = Self.lastSession(in: row)
    }

    private static func lastSession(in row: ProfileRow) -> LastSession? {
        guard let json = row.lastSession, let preview = try? json.decode(ProfileSessionPreview.self) else {
            return nil
        }
        let activity = preview.lastActive.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        return LastSession(
            title: text(preview.title) ?? text(preview.preview) ?? "",
            lastActive: activity,
            messageCount: preview.messageCount ?? 0)
    }

    private static func text(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// The `last_session` of a `profiles.list` row, typed. The contract's ProfileSessionPreview; the row keeps it raw.
struct ProfileSessionPreview: Decodable, Sendable, Equatable {
    var id: String
    var title: String?
    var preview: String?
    var lastActive: Double?
    var messageCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, preview
        case lastActive = "last_active"
        case messageCount = "message_count"
    }
}
