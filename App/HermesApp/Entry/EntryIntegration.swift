import CoreSpotlight
import Foundation
import HermesKit
import HermesUI

/// Owns the ways into the app from outside: App Intents and Siri, Quick Entry, the Share extension and Spotlight.
///
/// Everything that talks to a server happens here, in the app's process. The intents, the controls and the Share
/// extension only leave a request (in memory or in the shared container) and this class carries it out.
@MainActor
final class EntryIntegration {
    let quickEntry: QuickEntryCoordinator
    private let model: ShellModel
    private let connections: ConnectionsModel
    private let integration: AppIntegration
    private let outbound: OutboundCoordinator
    private let roster: BotRosterService
    private let sharedDirectory: URL?
    private var handledShares: Set<String> = []
    private var pendingActionPoll: Task<Void, Never>?

    init(model: ShellModel, connections: ConnectionsModel, integration: AppIntegration) {
        let quickEntry = QuickEntryCoordinator()
        let localDirectory = IntentDirectory.directory
        let sharedDirectory = integration.sharedContainer.directory
        let spotlight = SpotlightIndexer(directory: localDirectory)
        let directory = ChatDirectoryObserver(
            model: model, quickEntry: quickEntry, sharedDirectory: sharedDirectory, localDirectory: localDirectory,
            spotlight: spotlight)
        let outbound = OutboundCoordinator(
            model: model, lastUsedID: { directory.lastChat?.id },
            chatStarter: ServerChatStarter(connections: connections))
        let roster = BotRosterService(connections: connections, directory: localDirectory) { saved in
            spotlight.update(bots: saved.bots.map { SpotlightBot(name: $0.name, title: $0.title) })
            HermesShortcuts.updateAppShortcutParameters()
        }
        let executor = IntentExecutor(
            model: model, connections: connections, outbound: outbound, quickEntry: quickEntry, roster: roster,
            directory: directory)

        self.quickEntry = quickEntry
        self.model = model
        self.connections = connections
        self.integration = integration
        self.outbound = outbound
        self.roster = roster
        self.sharedDirectory = sharedDirectory

        AppCommandCenter.shared.handler = { request in await executor.perform(request) }
        directory.start()
        roster.start()
    }

    /// Whether a server is saved. Quick Entry needs one to send anything.
    var hasServer: Bool { !connections.isEmpty }

    // MARK: Quick Entry

    /// Sends what the user typed in the Quick Entry sheet.
    func sendQuickEntry(text: String, target: OutboundTarget) {
        let message = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }
        outbound.submit(OutboundMessage(text: message, target: target, createdAt: Date()))
    }

    // MARK: Becoming active

    /// Called when the app comes to the front and at launch.
    func becameActive() {
        integration.settingsMayHaveChanged()
        watchForPendingAction()
        drainShares()
    }

    /// The Action button and the Control Center control can run outside the app and leave a request behind. The
    /// request may land a moment after the app comes forward, so look for a few seconds.
    private func watchForPendingAction() {
        pendingActionPoll?.cancel()
        pendingActionPoll = Task { [weak self] in
            for _ in 0..<10 {
                guard let self, !Task.isCancelled else { return }
                if self.takePendingAction() { return }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }

    private func takePendingAction() -> Bool {
        guard let sharedDirectory, let action = PendingActionStore(directory: sharedDirectory).consume(now: Date())
        else { return false }
        switch action.kind {
        case .quickEntry:
            quickEntry.present(prefill: action.prefill)
        }
        return true
    }

    // MARK: Links and Spotlight

    func handle(url: URL) {
        if HermesURL.shareID(from: url) != nil {
            drainShares()
        } else if let route = HermesURL.quickEntryRoute(from: url) {
            quickEntry.present(prefill: route.prefill)
        }
    }

    /// A tap on a Spotlight result: a chat opens, and a bot starts a new chat as that bot.
    func handle(activity: NSUserActivity) {
        guard let identifier = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String,
            let target = SpotlightPlanner.target(of: identifier)
        else { return }
        switch target {
        case .chat(let id):
            open(chatID: id)
        case .bot(let name):
            startChat(withBot: name)
        }
    }

    /// The chat list may not have loaded yet when Spotlight opens the app, so wait for the chat for a while.
    private func open(chatID id: String) {
        Task { [weak self] in
            for _ in 0..<40 {
                guard let self else { return }
                if self.model.session(id: id) != nil {
                    self.model.open(id)
                    return
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func startChat(withBot name: String) {
        Task { [weak self] in
            guard let self, let bot = self.roster.roster.bot(named: name) else { return }
            if await self.roster.select(bot) == .selected {
                await self.openNewChat(profile: bot.name)
            }
        }
    }

    /// A new chat from outside the chat list: a chat on the server when one is saved, else the local placeholder.
    private func openNewChat(profile: String?) async {
        switch NewChatPolicy.kind(hasServer: hasServer) {
        case .placeholder:
            model.newChat()
        case .server:
            // A server that will not make the chat leaves the chat list as it was.
            _ = try? await outbound.startServerChat(profile: profile)
        }
    }

    // MARK: Shares

    /// Sends the shares the Share extension left in the shared container. Each share goes out once. A share is deleted
    /// once its message has been sent. A message kept as a draft keeps its share on disk, marked, and the next launch
    /// puts it back as a draft. It is never sent.
    func drainShares() {
        guard let sharedDirectory, hasServer else { return }
        let outbox = ShareOutbox(directory: sharedDirectory)
        outbox.purge(now: Date())
        for payload in outbox.pending() {
            guard handledShares.insert(payload.id).inserted else { continue }
            if payload.keptAsDraft {
                restoreDraft(payload, from: outbox)
            } else {
                deliver(payload, from: outbox)
            }
        }
    }

    private func deliver(_ payload: SharePayload, from outbox: ShareOutbox) {
        let id = payload.id
        outbound.submit(message(for: payload, from: outbox)) { outcome in
            switch outcome {
            case .sent:
                outbox.remove(id: id)
            case .keptAsDraft:
                // An unmarked share would be sent at the next launch, so one that cannot be marked is removed instead.
                if !outbox.markKeptAsDraft(id: id) { outbox.remove(id: id) }
            }
        }
    }

    /// Puts a share that an earlier launch kept as a draft back into a composer. The share leaves the outbox once it is
    /// in the composer, and it is not sent.
    private func restoreDraft(_ payload: SharePayload, from outbox: ShareOutbox) {
        guard outbound.restoreDraft(message(for: payload, from: outbox)) else { return }
        outbox.remove(id: payload.id)
    }

    private func message(for payload: SharePayload, from outbox: ShareOutbox) -> OutboundMessage {
        let attachments = payload.attachments.compactMap { file in
            outbox.data(of: file, in: payload.id).map { file.composerAttachment(data: $0) }
        }
        let target: OutboundTarget =
            switch payload.destination {
            case .newChat: .newChat
            case .chat(let sessionID): .chat(sessionID)
            }
        return OutboundMessage(
            id: payload.id, text: payload.text, attachments: attachments, target: target, createdAt: Date())
    }
}
