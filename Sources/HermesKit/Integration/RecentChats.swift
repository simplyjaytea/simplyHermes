import Foundation

/// A chat as the Share sheet lists it.
public struct RecentChat: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// A short time label such as `14:05` or `Yesterday`. May be empty.
    public var subtitle: String

    public init(id: String, title: String, subtitle: String = "") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }
}

/// The chats the Share extension offers as destinations.
///
/// The app writes it to the shared container when the chat list changes. The extension only reads it: it never opens
/// a connection. Only titles are stored, never messages.
public struct RecentChatsSnapshot: Codable, Equatable, Sendable {
    public static let fileName = "recent-chats.json"
    /// Chats kept, in the order the app lists them.
    public static let limit = 10

    public var chats: [RecentChat]
    public var updatedAt: Date

    /// - Parameter limit: how many chats to keep. The Share sheet uses the default; the Siri chat picker keeps more.
    public init(chats: [RecentChat], updatedAt: Date, limit: Int = RecentChatsSnapshot.limit) {
        self.chats = Array(chats.prefix(max(0, limit)))
        self.updatedAt = updatedAt
    }

    /// Same chats, ignoring `updatedAt`; used to skip writes that change nothing.
    public func hasSameContent(as other: RecentChatsSnapshot) -> Bool {
        chats == other.chats
    }

    public static func store(directory: URL) -> JSONFileStore<RecentChatsSnapshot> {
        JSONFileStore(directory: directory, fileName: fileName)
    }
}

/// One row of the Share sheet's destination list.
public struct ShareDestination: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var destination: SharePayload.Destination

    public init(id: String, title: String, subtitle: String? = nil, destination: SharePayload.Destination) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.destination = destination
    }

    public static let newChat = ShareDestination(id: "new", title: "New chat", destination: .newChat)

    /// New chat first, then the recent chats. Without a snapshot (no App Group yet, or the app never ran) only
    /// New chat is offered.
    public static func list(recent: RecentChatsSnapshot?) -> [ShareDestination] {
        let chats = (recent?.chats ?? []).map { chat in
            ShareDestination(
                id: "chat:" + chat.id,
                title: chat.title.isEmpty ? "Untitled chat" : chat.title,
                subtitle: chat.subtitle.isEmpty ? nil : chat.subtitle,
                destination: .chat(sessionID: chat.id))
        }
        return [newChat] + chats
    }
}
