import Foundation

/// What the "Keep bots live" control in Control Center shows.
///
/// The setting lives in the App Group, so the control (which runs in the widget extension) and the app read the same
/// value. Without the App Group nothing is shared: the control then reads as off and is disabled, instead of
/// pretending to change something.
public struct KeepBotsLiveControlState: Equatable, Sendable {
    public var isOn: Bool
    public var isAvailable: Bool

    /// - Parameters:
    ///   - isOn: the saved setting.
    ///   - groupAvailable: whether the App Group container could be used.
    public init(isOn: Bool, groupAvailable: Bool) {
        self.isOn = groupAvailable && isOn
        isAvailable = groupAvailable
    }

    /// The word under the control's title.
    public func valueText(isOn: Bool) -> String {
        guard isAvailable else { return "Unavailable" }
        return isOn ? "On" : "Off"
    }
}

/// What the "Stop all turns" control in Control Center shows, from the snapshot the app keeps for widgets.
public struct StopAllControlState: Equatable, Sendable {
    /// Turns running, or `nil` when the snapshot is missing or old and so cannot say.
    public var runningTurns: Int?
    /// Off only when a fresh snapshot says nothing is running. When unsure the control stays usable.
    public var isEnabled: Bool

    public init(snapshot: WidgetSnapshot?, now: Date) {
        guard let snapshot, !snapshot.isStale(at: now) else {
            runningTurns = nil
            isEnabled = true
            return
        }
        runningTurns = snapshot.activeBotCount
        isEnabled = snapshot.activeBotCount > 0 || !snapshot.approvals.isEmpty
    }

    /// The control's title: the count when it is known and above zero.
    public var title: String {
        switch runningTurns {
        case let count? where count == 1: "Stop 1 turn"
        case let count? where count > 1: "Stop \(count) turns"
        default: "Stop all turns"
        }
    }
}

/// The identifiers of the controls, shared by the app (to reload them) and the widget extension (to declare them).
public enum ControlKind {
    public static let askHermes = "com.simplyjaytea.simplyhermes.control.ask"
    public static let stopAll = "com.simplyjaytea.simplyhermes.control.stopAll"
    public static let keepBotsLive = "com.simplyjaytea.simplyhermes.control.keepBotsLive"
}
