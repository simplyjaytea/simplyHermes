import HermesKit
import HermesUI
import OSLog
import Observation
import UIKit
import WidgetKit

/// Watches the shell's chats and drives the Live Activities, Keep bots live and the widget cache.
///
/// A Live Activity starts when a turn starts streaming and follows it through approvals until it
/// ends. Until Bot Mode lands (WP-5x) the widget lists chats as its "bots".
@MainActor
final class LiveTurnMonitor {
    private let model: ShellModel
    private let activities: LiveActivityController
    private let keepAlive: KeepBotsLiveService
    private let widgetStore: WidgetSnapshotStore?
    private var lastWidgetSnapshot: WidgetSnapshot?
    /// Chats with a turn followed by a Live Activity, and when the turn started.
    private var startedAt: [String: Date] = [:]
    /// Chats stopped from a Live Activity or widget, so their final state reads "Stopped".
    private var stopped: Set<String> = []
    /// The approval each chat waits on (its row id), to notice one appearing and one being answered.
    private var waitingApprovals: [String: String] = [:]
    private let notifications: LocalNotifications
    private let logger = Logger(subsystem: "com.simplyjaytea.simplyhermes", category: "LiveTurnMonitor")

    init(
        model: ShellModel,
        activities: LiveActivityController,
        keepAlive: KeepBotsLiveService,
        sharedContainer: SharedContainer.Resolution,
        notifications: LocalNotifications = .shared
    ) {
        self.model = model
        self.notifications = notifications
        self.activities = activities
        self.keepAlive = keepAlive
        widgetStore = sharedContainer.directory.map(WidgetSnapshotStore.init(directory:))
        if case .unavailable(let tried) = sharedContainer {
            let groups = tried.joined(separator: ", ")
            logger.notice("No App Group container (tried \(groups, privacy: .public)); widgets show Open simplyHermes")
        }
    }

    func start() {
        observe()
    }

    func markStopped(_ sessionID: String) {
        stopped.insert(sessionID)
    }

    private func observe() {
        withObservationTracking {
            refresh()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func refresh(now: Date = .now) {
        var running = 0
        for session in model.sessions {
            let id = session.id
            let isStreaming = model.isStreaming(id)
            let approval = model.pendingApproval(in: id)
            if isStreaming || (approval != nil && startedAt[id] != nil) {
                let started = startedAt[id] ?? now
                startedAt[id] = started
                running += 1
                let state = turnState(for: session, approval: approval, startedAt: started)
                activities.apply(sessionID: id, serverName: session.serverName, state: state, now: now)
            } else if let started = startedAt.removeValue(forKey: id) {
                var state = turnState(for: session, approval: nil, startedAt: started)
                state.phase = stopped.remove(id) == nil ? .done : .stopped
                activities.finish(sessionID: id, state: state)
                notifyTurnEnded(session, startedAt: started, stopped: state.phase == .stopped, now: now)
            }
            notifyApprovalChange(session, approval: approval, now: now)
        }
        keepAlive.update(runningTurns: running)
        activities.keepsAppAlive = keepAlive.isHolding
        writeWidgetSnapshot(now: now)
    }

    private func turnState(for session: ChatSessionSummary, approval: ShellMessage?, startedAt: Date) -> LiveTurnState {
        let last = model.transcripts[session.id]?.last { $0.kind != .approval && $0.kind != .user }
        let phase: LiveTurnState.Phase
        if approval != nil {
            phase = .waitingForApproval
        } else if case .tool = last?.kind {
            phase = .runningTool
        } else {
            phase = .thinking
        }
        return LiveTurnState(
            phase: phase,
            botName: "Hermes",
            title: session.title,
            lastLine: last?.text ?? "",
            pendingCommand: approval?.text,
            startedAt: startedAt
        )
    }

    // MARK: Notifications

    private func notificationContext(now: Date) -> NotificationContext {
        let servers = Set(model.sessions.filter { !$0.id.hasPrefix("local-") }.map(\.serverName))
        return NotificationContext(
            appIsActive: UIApplication.shared.applicationState == .active, chatOnScreen: model.selectedSessionID,
            multipleServers: servers.count > 1, now: now)
    }

    private func notificationChat(_ session: ChatSessionSummary) -> NotificationChat {
        NotificationChat(
            id: session.id, title: session.title,
            serverName: session.id.hasPrefix("local-") ? nil : session.serverName)
    }

    private func notifyTurnEnded(_ session: ChatSessionSummary, startedAt: Date, stopped: Bool, now: Date) {
        let reply = model.transcripts[session.id]?.last { $0.kind == .assistant }?.text ?? ""
        notifications.handle(
            .turnEnded(
                notificationChat(session), startedAt: startedAt, endedAt: now, outcome: stopped ? .stopped : .done,
                reply: reply),
            context: notificationContext(now: now))
    }

    private func notifyApprovalChange(_ session: ChatSessionSummary, approval: ShellMessage?, now: Date) {
        let id = session.id
        let previous = waitingApprovals[id]
        guard previous != approval?.id else { return }
        if let previous {
            notifications.handle(
                .approvalResolved(chatID: id, requestID: previous), context: notificationContext(now: now))
        }
        waitingApprovals[id] = approval?.id
        if let approval {
            notifications.handle(
                .approvalWaiting(notificationChat(session), requestID: approval.id, command: approval.text),
                context: notificationContext(now: now))
        }
    }

    /// Writes only when what a widget shows changed, then reloads the widgets.
    private func writeWidgetSnapshot(now: Date) {
        guard let widgetStore else { return }
        let snapshot = WidgetSnapshot(
            bots: model.sessions.prefix(6).map { session in
                let isStreaming = model.isStreaming(session.id)
                let waiting = model.pendingApproval(in: session.id) != nil
                let status = waiting ? "Waiting for you" : (isStreaming ? "Working" : "Idle")
                return WidgetSnapshot.Bot(
                    id: session.id, name: session.title, isActive: isStreaming || waiting, statusLine: status)
            },
            approvals: model.sessions.compactMap { session in
                model.pendingApproval(in: session.id).map {
                    WidgetSnapshot.Approval(sessionID: session.id, botName: session.title, command: $0.text)
                }
            },
            updatedAt: now
        )
        if let lastWidgetSnapshot, lastWidgetSnapshot.hasSameContent(as: snapshot) { return }
        do {
            try widgetStore.save(snapshot)
            lastWidgetSnapshot = snapshot
            WidgetCenter.shared.reloadAllTimelines()
            ControlCenter.shared.reloadControls(ofKind: ControlKind.stopAll)
        } catch {
            logger.error("Widget snapshot write failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
