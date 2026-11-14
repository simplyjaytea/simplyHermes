import Foundation
import HermesKit
import HermesUI
import Observation

/// Watches the chat list and keeps the places that need it up to date.
///
/// - The Share extension reads the recent chats from the shared container to offer them as destinations.
/// - Siri's chat picker reads a longer list kept in the app's own folder.
/// - Spotlight gets the chat titles.
/// - Quick Entry and "Ask Hermes" follow up in the chat the user used last, so that chat is remembered here.
///
/// Only titles and time labels are written, never messages. A list that is still empty (the server has not answered
/// yet) never replaces a saved one, so the last known chats stay available while the app connects.
@MainActor
final class ChatDirectoryObserver {
    private static let lastChatKey = "lastChat"
    private static let lastChatServerKey = "lastChatServer"

    private let model: ShellModel
    private let quickEntry: QuickEntryCoordinator
    private let sharedStore: JSONFileStore<RecentChatsSnapshot>?
    private let localStore: JSONFileStore<RecentChatsSnapshot>
    private let spotlight: SpotlightIndexer
    private let defaults: UserDefaults
    private var writtenShared: RecentChatsSnapshot?
    private var writtenLocal: RecentChatsSnapshot?
    private var hasListedChats = false

    private var recordedChat: RecentChat?
    /// The saved server `recordedChat` belongs to. Nil for a chat saved before this was kept: it counts for any server.
    private var recordedServer: String?

    /// The chat the user used last, kept with its title so it can be named before the chat list loads. Nil while
    /// another server is active, because the chat id means nothing there.
    var lastChat: RecentChat? {
        if let recordedServer, let active = model.activeServerID?(), recordedServer != active { return nil }
        return recordedChat
    }

    init(
        model: ShellModel, quickEntry: QuickEntryCoordinator, sharedDirectory: URL?, localDirectory: URL,
        spotlight: SpotlightIndexer, defaults: UserDefaults = .standard
    ) {
        self.model = model
        self.quickEntry = quickEntry
        sharedStore = sharedDirectory.map { RecentChatsSnapshot.store(directory: $0) }
        localStore = RecentChatsSnapshot.store(directory: localDirectory)
        self.spotlight = spotlight
        self.defaults = defaults
        recordedChat = defaults.data(forKey: Self.lastChatKey).flatMap {
            try? JSONDecoder().decode(RecentChat.self, from: $0)
        }
        recordedServer = defaults.string(forKey: Self.lastChatServerKey)
        quickEntry.lastChat = lastChat
    }

    func start() {
        observe()
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh() {
        let listed = model.sessions.filter { model.serverSessionIDs.contains($0.id) }
        noteSelection()
        if quickEntry.lastChat != lastChat { quickEntry.lastChat = lastChat }
        if !listed.isEmpty { hasListedChats = true }
        guard hasListedChats else { return }
        let chats = listed.map { RecentChat(id: $0.id, title: $0.title, subtitle: $0.subtitle) }
        write(chats)
        spotlight.update(
            chats: listed.map {
                SpotlightChat(id: $0.id, title: $0.title, detail: $0.subtitle.isEmpty ? nil : $0.subtitle)
            })
    }

    /// Writes the lists only when they changed, so a refresh that changes nothing touches no file.
    private func write(_ chats: [RecentChat]) {
        let now = Date()
        let shared = RecentChatsSnapshot(chats: chats, updatedAt: now)
        if let sharedStore, writtenShared?.hasSameContent(as: shared) != true {
            do {
                try sharedStore.save(shared)
                writtenShared = shared
            } catch {
                writtenShared = nil
            }
        }
        let local = RecentChatsSnapshot(chats: chats, updatedAt: now, limit: IntentDirectory.chatLimit)
        if writtenLocal?.hasSameContent(as: local) != true {
            do {
                try localStore.save(local)
                writtenLocal = local
            } catch {
                writtenLocal = nil
            }
        }
    }

    /// The chat on screen is the one used last, when it is a server chat.
    private func noteSelection() {
        guard let id = model.selectedSessionID, model.serverSessionIDs.contains(id), let session = model.session(id: id)
        else { return }
        // The chat's own server must be the active one: right after a switch the selection is still the old server's.
        guard let owner = model.chatServer(of: id), owner == model.activeServerID?() else { return }
        let chat = RecentChat(id: id, title: session.title, subtitle: session.subtitle)
        guard chat != recordedChat || owner != recordedServer else { return }
        recordedChat = chat
        recordedServer = owner
        quickEntry.lastChat = chat
        defaults.set(owner, forKey: Self.lastChatServerKey)
        if let data = try? JSONEncoder().encode(chat) {
            defaults.set(data, forKey: Self.lastChatKey)
        }
    }
}
