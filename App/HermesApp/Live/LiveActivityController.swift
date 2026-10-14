import ActivityKit
import HermesKit
import OSLog

/// Starts, updates and ends one Live Activity per running turn.
///
/// Updates go through `LiveUpdateThrottle`: at most one per second, phase changes at once. Without
/// push, an activity can only change while the app runs. Each update therefore carries a stale date;
/// if the app is suspended (Keep bots live off, or iOS closed the app) the activity turns stale and
/// reads "Open simplyHermes to refresh" (fallback A in plans/ios-integration.md).
@MainActor
final class LiveActivityController {
    /// Without updates for this long, the activity shows as stale.
    static let staleAfter: TimeInterval = 90
    /// How long a finished activity stays on the Lock Screen.
    static let finishedLinger: TimeInterval = 10

    private struct Tracked {
        let activity: Activity<BotActivityAttributes>
        var throttle = LiveUpdateThrottle()
        var held: LiveTurnState?
        var flush: Task<Void, Never>?
    }

    private var tracked: [String: Tracked] = [:]
    private let logger = Logger(subsystem: "com.simplyjaytea.simplyhermes", category: "LiveActivity")

    /// While Keep bots live holds the app awake, updates keep flowing, so nothing goes stale.
    var keepsAppAlive = false

    /// Ends activities left over from an earlier run; their turns cannot be followed anymore.
    func endLeftovers() async {
        for activity in Activity<BotActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    func apply(sessionID: String, serverName: String, state: LiveTurnState, now: Date = .now) {
        guard var entry = tracked[sessionID] else {
            start(sessionID: sessionID, serverName: serverName, state: state, now: now)
            return
        }
        switch entry.throttle.decide(state, now: now) {
        case .sendNow:
            entry.flush?.cancel()
            entry.flush = nil
            entry.held = nil
            entry.throttle.markSent(state, at: now)
            tracked[sessionID] = entry
            send(state, to: entry.activity)
        case .sendAt(let due):
            entry.held = state
            if entry.flush == nil {
                let delay = max(0, due.timeIntervalSince(now))
                entry.flush = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    self?.flushHeld(sessionID)
                }
            }
            tracked[sessionID] = entry
        }
    }

    /// Shows the final state for a moment, then removes the activity.
    func finish(sessionID: String, state: LiveTurnState) {
        guard let entry = tracked.removeValue(forKey: sessionID) else { return }
        entry.flush?.cancel()
        let id = entry.activity.id
        let content = ActivityContent(state: state, staleDate: nil)
        let dismissal = ActivityUIDismissalPolicy.after(.now.addingTimeInterval(Self.finishedLinger))
        Task.detached {
            await Self.activity(id: id)?.end(content, dismissalPolicy: dismissal)
        }
    }

    private func start(sessionID: String, serverName: String, state: LiveTurnState, now: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let activity = try Activity.request(
                attributes: BotActivityAttributes(sessionID: sessionID, serverName: serverName),
                content: content(for: state),
                pushType: nil
            )
            var entry = Tracked(activity: activity)
            entry.throttle.markSent(state, at: now)
            tracked[sessionID] = entry
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func flushHeld(_ sessionID: String) {
        guard var entry = tracked[sessionID], let held = entry.held else { return }
        entry.held = nil
        entry.flush = nil
        entry.throttle.markSent(held, at: .now)
        tracked[sessionID] = entry
        send(held, to: entry.activity)
    }

    private func send(_ state: LiveTurnState, to activity: Activity<BotActivityAttributes>) {
        let id = activity.id
        let content = content(for: state)
        Task.detached {
            await Self.activity(id: id)?.update(content)
        }
    }

    /// `Activity` is not `Sendable`, so background tasks look it up by ID instead of capturing it.
    nonisolated private static func activity(id: String) -> Activity<BotActivityAttributes>? {
        Activity<BotActivityAttributes>.activities.first { $0.id == id }
    }

    private func content(for state: LiveTurnState) -> ActivityContent<LiveTurnState> {
        ActivityContent(state: state, staleDate: keepsAppAlive ? nil : .now.addingTimeInterval(Self.staleAfter))
    }
}
