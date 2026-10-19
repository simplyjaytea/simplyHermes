import SwiftUI
import WidgetKit

/// The one widget extension simplyHermes ships besides the Share extension (free signing allows few App IDs): the
/// Bots widget for the Home and Lock Screen, the bot Live Activity with its Dynamic Island, and the Control Center
/// controls.
@main
struct HermesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BotsWidget()
        BotLiveActivityWidget()
        AskHermesControl()
        StopAllControl()
        KeepBotsLiveControl()
    }
}
