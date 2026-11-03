import Foundation

/// Home-screen quick actions (feature B): the long-press menu on the app icon.
///
/// Two fixed actions, New chat and Search chats, plus one for the last chat used. A chat action names its chat
/// exactly: whether it is a server chat or a local one, the server it belongs to, and its id. It opens that chat and
/// nothing else. A server chat whose server can't be reached opens in its own not-connected state; it never falls back
/// to a local chat, and no action ever picks Online or Local on the user's behalf.

/// Whether a chat lives on a server or only on this iPhone.
public enum QuickActionChatKind: String, Codable, Sendable {
    case server
    case local
}

/// The exact chat a quick action opens.
public struct QuickActionChat: Codable, Equatable, Sendable {
    public var kind: QuickActionChatKind
    /// The saved server's id. Nil for a local chat, which belongs to no server.
    public var connectionID: String?
    /// The chat's id as the chat list knows it: a session id, or `local-<uuid>` for a local chat.
    public var chatID: String

    public init(kind: QuickActionChatKind, connectionID: String?, chatID: String) {
        self.kind = kind
        self.connectionID = connectionID
        self.chatID = chatID
    }

    /// A server chat on `connectionID`.
    public static func server(_ chatID: String, connectionID: String) -> Self {
        Self(kind: .server, connectionID: connectionID, chatID: chatID)
    }

    /// A chat that exists only on this iPhone.
    public static func local(_ chatID: String) -> Self {
        Self(kind: .local, connectionID: nil, chatID: chatID)
    }

    /// True when the parts fit together: a server chat names its server, and a local chat id is `local-<uuid>`.
    public var isWellFormed: Bool {
        guard !chatID.isEmpty else { return false }
        switch kind {
        case .server:
            return !(connectionID ?? "").isEmpty && !chatID.hasPrefix("local-")
        case .local:
            return connectionID == nil && chatID.hasPrefix("local-")
                && UUID(uuidString: String(chatID.dropFirst("local-".count))) != nil
        }
    }
}

/// What a quick action asks for.
public enum QuickActionRoute: Equatable, Sendable {
    /// The same action as the New chat button: it follows the default mode.
    case newChat
    /// The chat list with search open.
    case searchChats
    /// Exactly this chat.
    case openChat(QuickActionChat)

    static let typePrefix = "com.simplyjaytea.simplyhermes.quick."

    /// The shortcut item's `type`.
    public var type: String {
        switch self {
        case .newChat: Self.typePrefix + "newChat"
        case .searchChats: Self.typePrefix + "searchChats"
        case .openChat: Self.typePrefix + "openChat"
        }
    }

    /// The shortcut item's `userInfo`, as strings.
    public var userInfo: [String: String] {
        guard case .openChat(let chat) = self else { return [:] }
        var info = ["kind": chat.kind.rawValue, "chat": chat.chatID]
        if let connection = chat.connectionID { info["connection"] = connection }
        return info
    }

    /// Reads a shortcut item back. Nil for an unknown type or a chat action whose parts don't fit, so a malformed
    /// action never opens something else.
    public init?(type: String, userInfo: [String: String]) {
        switch type {
        case Self.typePrefix + "newChat":
            self = .newChat
        case Self.typePrefix + "searchChats":
            self = .searchChats
        case Self.typePrefix + "openChat":
            guard let kind = userInfo["kind"].flatMap(QuickActionChatKind.init(rawValue:)),
                let chatID = userInfo["chat"]
            else { return nil }
            let chat = QuickActionChat(kind: kind, connectionID: userInfo["connection"], chatID: chatID)
            guard chat.isWellFormed else { return nil }
            self = .openChat(chat)
        default:
            return nil
        }
    }
}

/// What the app does for a quick action.
public enum QuickActionOutcome: Equatable, Sendable {
    case newChat
    case searchChats
    /// Open this chat on the server already in use, or this local chat.
    case open(chatID: String)
    /// Make this saved server the one in use, then open its chat.
    case switchServerThenOpen(connectionID: String, chatID: String)
    /// The chat's server was removed, or the local chat was deleted. Show the chat list and drop the shortcut.
    case stale
}

/// Decides what a quick action does. Pure: it sees only which servers are saved, which one is in use and whether a
/// local chat exists. It never sees whether a server is reachable, so reachability can't turn a server chat into
/// anything else.
public enum QuickActionPlanner {
    public static func outcome(
        for route: QuickActionRoute, activeConnectionID: String?, savedConnectionIDs: Set<String>,
        localChatExists: (String) -> Bool
    ) -> QuickActionOutcome {
        switch route {
        case .newChat:
            return .newChat
        case .searchChats:
            return .searchChats
        case .openChat(let chat):
            switch chat.kind {
            case .local:
                return localChatExists(chat.chatID) ? .open(chatID: chat.chatID) : .stale
            case .server:
                guard let connection = chat.connectionID, savedConnectionIDs.contains(connection) else { return .stale }
                return connection == activeConnectionID
                    ? .open(chatID: chat.chatID) : .switchServerThenOpen(connectionID: connection, chatID: chat.chatID)
            }
        }
    }
}

/// One item of the icon's menu, without UIKit types so it can be tested on Linux.
public struct QuickActionItem: Equatable, Sendable {
    public var route: QuickActionRoute
    public var title: String
    public var subtitle: String?
    /// An SF Symbol name.
    public var symbol: String
}

/// The last chat used, with its title, for the dynamic item.
public struct QuickActionLastChat: Codable, Equatable, Sendable {
    public var chat: QuickActionChat
    public var title: String

    public init(chat: QuickActionChat, title: String) {
        self.chat = chat
        self.title = title
    }
}

/// Builds the icon's menu.
public enum QuickActionMenu {
    /// What the last-chat item says when titles are hidden.
    public static let hiddenTitle = "Continue last chat"

    /// The fixed items, then the last chat (when there is one): New chat, Search chats, last chat.
    public static func items(lastChat: QuickActionLastChat?, showTitle: Bool) -> [QuickActionItem] {
        var items = [
            QuickActionItem(route: .newChat, title: "New chat", subtitle: nil, symbol: "square.and.pencil"),
            QuickActionItem(route: .searchChats, title: "Search chats", subtitle: nil, symbol: "magnifyingglass"),
        ]
        if let lastChat, lastChat.chat.isWellFormed {
            let title = lastChat.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let showsTitle = showTitle && !title.isEmpty
            items.append(
                QuickActionItem(
                    route: .openChat(lastChat.chat), title: showsTitle ? title : hiddenTitle,
                    subtitle: showsTitle ? "Last chat" : nil,
                    symbol: lastChat.chat.kind == .local ? "iphone" : "bubble.left.and.bubble.right"))
        }
        return items
    }

    /// Whether the remembered last chat may stay in the menu. A local chat that no longer exists goes. A server chat
    /// goes only once the server's list has loaded (`listedServerChats` is not nil) without it, so an empty list
    /// while the app connects doesn't drop it.
    public static func keeps(
        _ lastChat: QuickActionLastChat, savedConnectionIDs: Set<String>, listedServerChats: Set<String>?,
        localChatExists: (String) -> Bool
    ) -> Bool {
        switch lastChat.chat.kind {
        case .local:
            return localChatExists(lastChat.chat.chatID)
        case .server:
            guard let connection = lastChat.chat.connectionID, savedConnectionIDs.contains(connection) else {
                return false
            }
            guard let listedServerChats else { return true }
            return listedServerChats.contains(lastChat.chat.chatID)
        }
    }
}

/// Where the last chat and the title setting are kept.
public struct QuickActionStore: @unchecked Sendable {
    /// The Settings › Privacy toggle. On by default.
    public static let showTitleKey = "quickActions.showChatTitle"
    static let lastChatKey = "quickActions.lastChat"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var showTitle: Bool {
        defaults.object(forKey: Self.showTitleKey) as? Bool ?? true
    }

    public var lastChat: QuickActionLastChat? {
        get {
            defaults.data(forKey: Self.lastChatKey).flatMap {
                try? JSONDecoder().decode(QuickActionLastChat.self, from: $0)
            }
        }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.lastChatKey) }
    }
}
