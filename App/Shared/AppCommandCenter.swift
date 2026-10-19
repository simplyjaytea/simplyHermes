import Foundation
import HermesKit

/// Where intents hand their work to the app.
///
/// An intent runs in the app's process when the app is its target, and the app registers `handler` at launch. An
/// intent that ends up in another process (a control running in the widget extension, for example) finds no handler.
/// It then leaves what it can in the shared container for the app to pick up when it becomes active, and says so.
/// Extensions never open a connection to the server.
@MainActor
final class AppCommandCenter {
    static let shared = AppCommandCenter()

    /// Set by the app at launch. Carries a request out and reports what happened.
    var handler: (@MainActor (IntentRequest) async -> IntentOutcome)?

    func perform(_ request: IntentRequest) async -> IntentOutcome {
        if let handler {
            return await handler(request)
        }
        return leaveForApp(request)
    }

    /// The app is not in this process. Opening Quick Entry survives that: the request waits in the shared container.
    private func leaveForApp(_ request: IntentRequest) -> IntentOutcome {
        guard case .openQuickEntry(let prefill) = request, let directory = IntegrationStorage.sharedDirectory else {
            return .needsApp
        }
        do {
            try PendingActionStore(directory: directory)
                .post(PendingAction(kind: .quickEntry, prefill: prefill, createdAt: Date()))
            return .openedQuickEntry
        } catch {
            return .needsApp
        }
    }
}
