import AppIntents
import HermesKit
import HermesUI
import SwiftUI
import WidgetKit

// The Control Center controls. Like the widgets they never open a connection: they read what the app saved in the
// shared container and hand every action to an App Intent, which runs in the app.

/// "Ask Hermes": opens simplyHermes with the Quick Entry box ready.
struct AskHermesControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.askHermes) {
            ControlWidgetButton(action: OpenQuickEntryIntent()) {
                Label("Ask Hermes", systemImage: "text.bubble")
            }
        }
        .displayName("Ask Hermes")
        .description("Opens a box to type a message to Hermes.")
    }
}

/// "Stop all turns": the title shows how many turns run, from the snapshot the app keeps for widgets. The button is
/// off only when a fresh snapshot says nothing is running.
struct StopAllControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: StopAllControlState {
            StopAllControlState(snapshot: nil, now: Date())
        }

        func currentValue() async throws -> StopAllControlState {
            let snapshot = IntegrationStorage.sharedDirectory.flatMap { WidgetSnapshotStore(directory: $0).load() }
            return StopAllControlState(snapshot: snapshot, now: Date())
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.stopAll, provider: Provider()) { state in
            ControlWidgetButton(action: StopAllTurnsIntent()) {
                Label(state.title, systemImage: "stop.circle")
            }
            .tint(.red)
            .disabled(!state.isEnabled)
        }
        .displayName("Stop all turns")
        .description("Stops every bot turn that is running.")
    }
}

/// "Keep bots live": a switch kept in the App Group, shared with Settings in the app. Without an App Group it reads as
/// unavailable instead of pretending to change something.
struct KeepBotsLiveControl: ControlWidget {
    struct Provider: ControlValueProvider {
        var previewValue: KeepBotsLiveControlState {
            KeepBotsLiveControlState(isOn: false, groupAvailable: true)
        }

        func currentValue() async throws -> KeepBotsLiveControlState {
            KeepBotsLiveControlState(
                isOn: KeepBotsLiveSetting.store().bool(forKey: KeepBotsLiveSetting.key),
                groupAvailable: KeepBotsLiveSetting.isShared)
        }
    }

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: ControlKind.keepBotsLive, provider: Provider()) { state in
            ControlWidgetToggle(
                "Keep bots live", isOn: state.isOn, action: KeepBotsLiveToggleIntent()
            ) { isOn in
                Label(state.valueText(isOn: isOn), systemImage: isOn ? "bolt.fill" : "bolt.slash")
            }
            .disabled(!state.isAvailable)
        }
        .displayName("Keep bots live")
        .description("Keeps simplyHermes running in the background while a bot works.")
    }
}
