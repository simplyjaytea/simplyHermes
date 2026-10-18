import Foundation
import HermesKit

/// The chats and bots the app keeps on the phone for Siri and Shortcuts.
///
/// The app writes them as it learns them. The intents read them, so they can offer a chat or a bot even when the app
/// has not connected to a server yet. This folder belongs to the app alone; extensions use the shared container.
enum IntentDirectory {
    /// Chats kept for the chat picker.
    static let chatLimit = 50

    static var directory: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("simplyHermes", isDirectory: true)
            .appendingPathComponent("Integration", isDirectory: true)
    }

    static func chats() -> [RecentChat] {
        RecentChatsSnapshot.store(directory: directory).load()?.chats ?? []
    }

    static func roster() -> BotRoster {
        BotRoster.store(directory: directory).load() ?? BotRoster(bots: [], updatedAt: .distantPast)
    }
}
