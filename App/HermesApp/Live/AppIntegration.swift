import Foundation
import HermesKit
import HermesUI

/// Owns the iOS integrations: Live Activities, Keep bots live, the widget cache, and the handler
/// for Stop, Deny and Approve buttons outside the app.
@MainActor
final class AppIntegration {
    let sharedContainer: SharedContainer.Resolution
    private let activities = LiveActivityController()
    private let keepAlive = KeepBotsLiveService()
    private let monitor: LiveTurnMonitor

    init(model: ShellModel) {
        sharedContainer = SharedContainer.resolve(
            infoDictionary: Bundle.main.infoDictionary,
            containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
        )
        monitor = LiveTurnMonitor(
            model: model, activities: activities, keepAlive: keepAlive, sharedContainer: sharedContainer)

        let monitor = monitor
        LiveTurnActionCenter.shared.handler = { [weak model] action, sessionID in
            guard let model else { return }
            switch action {
            case .stop:
                monitor.markStopped(sessionID)
                model.stop(in: sessionID)
            case .deny:
                model.resolveApproval(in: sessionID, approved: false)
            case .approve:
                model.resolveApproval(in: sessionID, approved: true)
            }
        }

        let activities = activities
        Task {
            await activities.endLeftovers()
            monitor.start()
        }
    }
}
