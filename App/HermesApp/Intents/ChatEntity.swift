import AppIntents
import HermesKit

/// A chat that Siri and Shortcuts can pick. Only the id and the title travel.
struct ChatEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Chat" }
    static let defaultQuery = ChatQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }

    init(_ chat: RecentChat) {
        self.init(id: chat.id, title: chat.title.isEmpty ? "Untitled chat" : chat.title)
    }
}

/// Finds chats from the list the app saved last. It does not wait for a connection.
struct ChatQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [ChatEntity] {
        let chats = IntentDirectory.chats()
        return identifiers.compactMap { id in chats.first { $0.id == id }.map(ChatEntity.init) }
    }

    func entities(matching string: String) async throws -> [ChatEntity] {
        IntentDirectory.chats()
            .filter { $0.title.localizedCaseInsensitiveContains(string) }
            .map(ChatEntity.init)
    }

    func suggestedEntities() async throws -> [ChatEntity] {
        IntentDirectory.chats().prefix(10).map(ChatEntity.init)
    }
}
