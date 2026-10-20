import Foundation

/// A bot's Bot Chat is the session titled exactly `Bot Chat` on its profile. There is no stored id (plan 2.5, WP-42).
public enum BotChat {
    public static let title = "Bot Chat"

    /// Shown when `/new` is rewritten to `/compact` in a Bot Chat.
    public static let resetNoticeTitle = "This chat never resets"
    public static let resetNoticeBody =
        "Bot chats are one continuous conversation, so it compacts instead. Use Sessions for a throwaway chat."

    /// The draft to send. In a Bot Chat, `/new` and `/reset` become `/compact`. Everything else is unchanged.
    public static func rewrite(_ draft: String, inBotChat: Bool) -> String {
        guard inBotChat else { return draft }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "/new" || trimmed == "/reset" ? "/compact" : draft
    }
}

/// A row of `session.list {profile, title: "Bot Chat", include_hidden: true}`.
public struct BotChatRow: Sendable, Equatable, Codable {
    public var id: String
    public var resolvedID: String?
    public var rootTitle: String?
    public var title: String?
    public var liveMessageCount: Int?
    public var messageCount: Int?

    public init(
        id: String, resolvedID: String? = nil, rootTitle: String? = nil, title: String? = nil,
        liveMessageCount: Int? = nil, messageCount: Int? = nil
    ) {
        self.id = id
        self.resolvedID = resolvedID
        self.rootTitle = rootTitle
        self.title = title
        self.liveMessageCount = liveMessageCount
        self.messageCount = messageCount
    }

    enum CodingKeys: String, CodingKey {
        case id, title
        case resolvedID = "resolved_id"
        case rootTitle = "root_title"
        case liveMessageCount = "live_message_count"
        case messageCount = "message_count"
    }

    /// The session to open: the live compression tip, else the registry row.
    public var openID: String { resolvedID ?? id }

    /// True when this row is the Bot Chat: its lineage root is titled `Bot Chat`, or it has no root and is titled so.
    public var isBotChat: Bool {
        if let rootTitle, !rootTitle.isEmpty { return rootTitle == BotChat.title }
        return title == BotChat.title
    }
}

/// The outcome of looking for a Bot Chat. Fails closed: an error or an inconsistent answer never mints a new chat.
public enum BotChatLookup: Sendable, Equatable {
    /// The Bot Chat exists. `openID` is what to resume, `registryID` is the durable row.
    case found(openID: String, registryID: String)
    /// No Bot Chat exists yet, and the roster did not say one did. Creating one is allowed.
    case none
    /// The roster said a Bot Chat exists, but the lookup found none. Do not create one; report it.
    case inconsistent

    /// Resolves the rows of a `session.list` lookup. `rosterKnowsChat` is true when the roster row carried a
    /// `canonical_session`.
    public static func resolve(_ rows: [BotChatRow], rosterKnowsChat: Bool) -> BotChatLookup {
        if let match = rows.first(where: { $0.isBotChat }) {
            return .found(openID: match.openID, registryID: match.id)
        }
        return rosterKnowsChat ? .inconsistent : .none
    }
}
