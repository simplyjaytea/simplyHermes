import Foundation
import HermesKit
import Testing

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func snapshot(active: Int, approvals: Int = 0, age: TimeInterval = 0) -> WidgetSnapshot {
    WidgetSnapshot(
        bots: (0..<3).map { index in
            WidgetSnapshot.Bot(id: "b\(index)", name: "Bot \(index)", isActive: index < active, statusLine: "")
        },
        approvals: (0..<approvals).map { WidgetSnapshot.Approval(sessionID: "s\($0)", botName: "Bot", command: "ls") },
        updatedAt: now.addingTimeInterval(-age))
}

@Suite struct ControlStateTests {
    // MARK: Keep bots live

    @Test func theToggleShowsTheSavedSettingWhenTheGroupWorks() {
        let saved = KeepBotsLiveControlState(isOn: true, groupAvailable: true)
        #expect(saved.isOn && saved.isAvailable)
        #expect(saved.valueText(isOn: true) == "On" && saved.valueText(isOn: false) == "Off")
        let unsaved = KeepBotsLiveControlState(isOn: false, groupAvailable: true)
        #expect(!unsaved.isOn && unsaved.isAvailable)
    }

    @Test func withoutTheGroupTheToggleReadsOffAndUnavailable() {
        let state = KeepBotsLiveControlState(isOn: true, groupAvailable: false)
        #expect(!state.isOn && !state.isAvailable, "a setting that cannot be shared is not shown as on")
        #expect(state.valueText(isOn: true) == "Unavailable" && state.valueText(isOn: false) == "Unavailable")
    }

    // MARK: Stop all turns

    @Test func stopAllHasNoNumberWithoutAFreshSnapshot() {
        for state in [
            StopAllControlState(snapshot: nil, now: now),
            StopAllControlState(snapshot: snapshot(active: 2, age: WidgetSnapshot.staleAfter + 1), now: now),
        ] {
            #expect(state.runningTurns == nil && state.isEnabled && state.title == "Stop all turns")
        }
    }

    @Test func stopAllShowsTheCountOfRunningTurns() {
        let one = StopAllControlState(snapshot: snapshot(active: 1), now: now)
        #expect(one.runningTurns == 1 && one.isEnabled && one.title == "Stop 1 turn")
        let two = StopAllControlState(snapshot: snapshot(active: 2), now: now)
        #expect(two.runningTurns == 2 && two.title == "Stop 2 turns")
    }

    @Test func stopAllIsOffOnlyWhenAFreshSnapshotSaysNothingRuns() {
        let idle = StopAllControlState(snapshot: snapshot(active: 0), now: now)
        #expect(idle.runningTurns == 0 && !idle.isEnabled && idle.title == "Stop all turns")
        let waiting = StopAllControlState(snapshot: snapshot(active: 0, approvals: 1), now: now)
        #expect(waiting.isEnabled, "a chat that waits for approval can still be stopped")
    }

    // MARK: Identifiers

    @Test func controlKindsAreDistinct() {
        let kinds = [ControlKind.askHermes, ControlKind.stopAll, ControlKind.keepBotsLive]
        #expect(Set(kinds).count == 3)
        #expect(kinds.allSatisfy { $0.hasPrefix("com.simplyjaytea.simplyhermes.control.") })
    }
}
