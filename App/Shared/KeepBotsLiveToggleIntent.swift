import AppIntents
import HermesKit
import HermesUI
import WidgetKit

/// Flips "Keep bots live" from Control Center.
///
/// The switch lives in the App Group, so this works whether the intent runs in the widget extension or in the app.
/// The app reads the setting again when it becomes active and at the next change of a running turn.
struct KeepBotsLiveToggleIntent: SetValueIntent {
    static var title: LocalizedStringResource { "Keep bots live" }
    static var description: IntentDescription {
        IntentDescription("Keeps simplyHermes running in the background while a bot works.")
    }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Keep bots live")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        KeepBotsLiveSetting.store().set(value, forKey: KeepBotsLiveSetting.key)
        ControlCenter.shared.reloadControls(ofKind: ControlKind.keepBotsLive)
        return .result()
    }
}
