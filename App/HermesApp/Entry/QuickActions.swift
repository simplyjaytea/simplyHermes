import Foundation
import HermesKit
import HermesUI
import Observation
import UIKit

/// Receives home-screen quick actions from UIKit. A cold launch delivers the action before ``EntryIntegration``
/// exists, so it waits here until a handler is set.
@MainActor
final class QuickActionCenter {
    static let shared = QuickActionCenter()

    private var pending: QuickActionRoute?
    var handler: ((QuickActionRoute) -> Void)? {
        didSet {
            if let handler, let pending {
                self.pending = nil
                handler(pending)
            }
        }
    }

    func receive(_ item: UIApplicationShortcutItem) -> Bool {
        let info = (item.userInfo ?? [:]).compactMapValues { $0 as? String }
        guard let route = QuickActionRoute(type: item.type, userInfo: info) else { return false }
        receive(route)
        return true
    }

    func receive(_ route: QuickActionRoute) {
        if let handler {
            handler(route)
        } else {
            pending = route
        }
    }
}

/// Hands every scene's quick actions to ``QuickActionCenter``. SwiftUI still owns the windows.
@MainActor
final class QuickActionAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let item = options.shortcutItem { _ = QuickActionCenter.shared.receive(item) }
        // Only the app's own window scenes get the quick-action delegate. Every other role, such as the second
        // display of the CI's iPhone Duo, keeps SwiftUI's own configuration, since this delegate makes no window.
        // (Suspected cause of run 41525155659 hitting its 110-minute limit on that device.)
        guard connectingSceneSession.role == .windowApplication else { return connectingSceneSession.configuration }
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

@MainActor
final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(QuickActionCenter.shared.receive(shortcutItem))
    }
}

/// Carries out quick actions and keeps the icon's menu current (feature B).
///
/// - New chat runs the same action as the New chat button, so it follows the default mode.
/// - A chat action opens exactly its chat. A server chat whose server can't be reached opens in its own state; it
///   never becomes a local chat. A chat that is gone shows the chat list, and its item leaves the menu.
/// - The last chat used is remembered as the user opens chats and written to the menu when the app goes to the
///   background, with or without its title (Settings › Privacy).
@MainActor
final class QuickActionCoordinator {
    private let model: ShellModel
    private let connections: ConnectionsModel
    private let store: QuickActionStore

    init(model: ShellModel, connections: ConnectionsModel, store: QuickActionStore = QuickActionStore()) {
        self.model = model
        self.connections = connections
        self.store = store
    }

    func start() {
        observeSelection()
        QuickActionCenter.shared.handler = { [weak self] route in self?.perform(route) }
        #if DEBUG
            if let route = launchArgumentRoute() { QuickActionCenter.shared.receive(route) }
        #endif
    }

    // MARK: Performing

    private func perform(_ route: QuickActionRoute) {
        Task { [weak self] in
            guard let self else { return }
            let localExists = await self.localChatExists(route)
            let outcome = QuickActionPlanner.outcome(
                for: route, activeConnectionID: self.connections.active?.id.uuidString,
                savedConnectionIDs: Set(self.connections.connections.map(\.id.uuidString)),
                localChatExists: { _ in localExists })
            await self.carryOut(outcome)
        }
    }

    private func carryOut(_ outcome: QuickActionOutcome) async {
        switch outcome {
        case .newChat:
            model.newChat()
        case .searchChats:
            model.selectedSection = .chats
            model.selectedSessionID = nil
            model.chatSearchRequest += 1
        case .open(let id):
            await open(id)
        case .switchServerThenOpen(let connection, let id):
            if let uuid = UUID(uuidString: connection) { connections.setActive(uuid) }
            await open(id)
        case .stale:
            showListAndForgetLastChat()
        }
    }

    /// The chat list may still be loading at launch, so wait for the chat for a while. A server chat comes from the
    /// cache even when its server can't be reached, so an offline chat still opens in its own not-connected state.
    ///
    /// Giving up after the wait shows the list but keeps the last-chat item: a slow server switch is not a deleted
    /// chat. The menu refresh then drops the item only if the chat is really gone (a loaded list without it, a missing
    /// local chat, or a removed server), by the same rule as every other refresh.
    private func open(_ id: String) async {
        for _ in 0..<40 {
            if model.session(id: id) != nil {
                model.open(id)
                return
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        showList()
        refreshMenu()
    }

    private func showList() {
        model.selectedSection = .chats
        model.selectedSessionID = nil
    }

    /// The planner found the chat's server is no longer saved: the item can never open, so it goes.
    private func showListAndForgetLastChat() {
        showList()
        store.lastChat = nil
        refreshMenu()
    }

    private func localChatExists(_ route: QuickActionRoute) async -> Bool {
        guard case .openChat(let chat) = route, chat.kind == .local,
            let uuid = UUID(uuidString: String(chat.chatID.dropFirst("local-".count))),
            let store = LocalChatServices.shared?.store
        else { return false }
        return (try? await store.chat(uuid)) != nil
            || model.session(id: chat.chatID) != nil  // listed but not saved yet: an empty new local chat
    }

    // MARK: The menu

    /// Writes the icon's menu. Called when the app goes to the background and when it becomes active.
    ///
    /// The check for a local chat is async, so the write runs inside a background task: on the way to the
    /// background, iOS would otherwise suspend the app before the menu (and the title setting) is written.
    func refreshMenu() {
        let background = BackgroundTaskToken(name: "Quick action menu")
        Task { [weak self] in
            defer { background.end() }
            guard let self else { return }
            var last = self.store.lastChat
            if let current = last, !(await self.keeps(current)) {
                self.store.lastChat = nil
                last = nil
            }
            let items = QuickActionMenu.items(lastChat: last, showTitle: self.store.showTitle)
            UIApplication.shared.shortcutItems = items.map(Self.shortcutItem)
        }
    }

    private func keeps(_ last: QuickActionLastChat) async -> Bool {
        var localExists = false
        if last.chat.kind == .local, let uuid = UUID(uuidString: String(last.chat.chatID.dropFirst("local-".count))) {
            localExists = (try? await LocalChatServices.shared?.store.chat(uuid)) != nil
        }
        // The server's list counts only for the server in use, and only once it has loaded.
        let listed: Set<String>? =
            last.chat.connectionID == connections.active?.id.uuidString && !model.serverSessionIDs.isEmpty
            ? model.serverSessionIDs : nil
        return QuickActionMenu.keeps(
            last, savedConnectionIDs: Set(connections.connections.map(\.id.uuidString)), listedServerChats: listed,
            localChatExists: { _ in localExists })
    }

    private static func shortcutItem(_ item: QuickActionItem) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: item.route.type, localizedTitle: item.title, localizedSubtitle: item.subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: item.symbol),
            userInfo: item.route.userInfo.mapValues { $0 as NSString } as [String: NSSecureCoding])
    }

    // MARK: Remembering the last chat

    private func observeSelection() {
        withObservationTracking {
            noteSelection()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeSelection() }
        }
    }

    /// A placeholder chat (`new-…`) isn't remembered until it becomes a real chat.
    private func noteSelection(retry: Bool = true) {
        guard let id = model.selectedSessionID, let session = model.session(id: id) else { return }
        let chat: QuickActionChat
        if id.hasPrefix("local-") {
            chat = .local(id)
        } else if model.serverSessionIDs.contains(id), let active = connections.active?.id.uuidString {
            // The chat's own server, not the active one: right after a switch the selected chat can still be the old
            // server's. A chat whose model is not open yet has no server to read, so look again shortly.
            guard let owner = model.chatServer(of: id), owner == active else {
                if retry, model.chatServer(of: id) == nil {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(1))
                        self?.noteSelection(retry: false)
                    }
                }
                return
            }
            chat = .server(id, connectionID: owner)
        } else {
            return
        }
        let last = QuickActionLastChat(chat: chat, title: session.title)
        if store.lastChat != last { store.lastChat = last }
    }

    #if DEBUG
        /// UI tests can't long-press the home-screen icon. `-HermesQuickAction newChat|searchChats|<chat id>` runs the
        /// action at launch; a chat id starting with `local-` is a local chat, any other a chat on the active server.
        private func launchArgumentRoute() -> QuickActionRoute? {
            guard let value = UserDefaults.standard.string(forKey: "HermesQuickAction") else { return nil }
            switch value {
            case "newChat": return .newChat
            case "searchChats": return .searchChats
            default:
                if value.hasPrefix("local-") { return .openChat(.local(value)) }
                return .openChat(.server(value, connectionID: connections.active?.id.uuidString ?? ""))
            }
        }
    #endif
}

/// One `UIApplication` background task, ended exactly once: by ``end()`` or when iOS says time is up.
@MainActor
private final class BackgroundTaskToken {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
