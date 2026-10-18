import Foundation
import HermesKit
import HermesUI

/// Carries out what the intents, Siri and the controls ask for, inside the app.
///
/// The intents only describe a request (see ``IntentRequest``). The app holds the connection and the chats, so the work
/// happens here. Stop and Approve go through the same action center as the Live Activity buttons.
@MainActor
final class IntentExecutor {
    private let model: ShellModel
    private let connections: ConnectionsModel
    private let outbound: OutboundCoordinator
    private let quickEntry: QuickEntryCoordinator
    private let roster: BotRosterService
    private let directory: ChatDirectoryObserver

    init(
        model: ShellModel, connections: ConnectionsModel, outbound: OutboundCoordinator,
        quickEntry: QuickEntryCoordinator, roster: BotRosterService, directory: ChatDirectoryObserver
    ) {
        self.model = model
        self.connections = connections
        self.outbound = outbound
        self.quickEntry = quickEntry
        self.roster = roster
        self.directory = directory
    }

    func perform(_ request: IntentRequest) async -> IntentOutcome {
        switch request {
        case .ask(_, let chatID):
            return ask(request, chatID: chatID)
        case .askBot(let name, _):
            return await askBot(request, botName: name)
        case .newChat:
            return newChat(request)
        case .stopAll:
            return stopAll()
        case .approvePending:
            return approvePending()
        case .openQuickEntry(let prefill):
            quickEntry.present(prefill: prefill)
            return .openedQuickEntry
        }
    }

    /// A message needs a saved server. Without one it would only go to a local placeholder chat.
    private var hasServer: Bool { !connections.isEmpty }

    private func ask(_ request: IntentRequest, chatID: String?) -> IntentOutcome {
        guard hasServer else { return .notConnected }
        guard let message = IntentMapping.message(for: request, now: Date()) else { return .needsApp }
        outbound.submit(message)
        if let chatID {
            return .queued(chatTitle: model.session(id: chatID)?.title ?? "that chat")
        }
        return .queued(chatTitle: directory.lastChat?.title)
    }

    private func askBot(_ request: IntentRequest, botName: String) async -> IntentOutcome {
        guard hasServer else { return .notConnected }
        guard let bot = roster.roster.bot(named: botName) else { return .unknownBot(botName) }
        switch await roster.select(bot) {
        case .selected:
            break
        case .unknown:
            return .unknownBot(bot.title)
        case .notConnected:
            return .notConnected
        }
        // Built after the wait, so the message does not start its delivery time early.
        guard let message = IntentMapping.message(for: request, now: Date()) else { return .needsApp }
        outbound.submit(message)
        return .askedBot(name: bot.title)
    }

    private func newChat(_ request: IntentRequest) -> IntentOutcome {
        guard let message = IntentMapping.message(for: request, now: Date()) else {
            model.newChat()
            return .openedNewChat
        }
        guard hasServer else { return .notConnected }
        outbound.submit(message)
        return .queued(chatTitle: nil)
    }

    private func stopAll() -> IntentOutcome {
        let running = model.runningSessionIDs
        for id in running {
            LiveTurnActionCenter.shared.perform(.stop, sessionID: id)
        }
        return .afterStopping(running.count)
    }

    private func approvePending() -> IntentOutcome {
        let pending = model.allPendingApprovals.map {
            PendingApprovalRef(sessionID: $0.sessionID, chatTitle: $0.sessionTitle, command: $0.command)
        }
        switch ApprovalPicker.pick(pending) {
        case .nothing:
            return .nothingToApprove
        case .several(let count):
            return .severalToApprove(count: count)
        case .approve(let approval):
            LiveTurnActionCenter.shared.perform(.approve, sessionID: approval.sessionID)
            return .approved(command: approval.command)
        }
    }
}
