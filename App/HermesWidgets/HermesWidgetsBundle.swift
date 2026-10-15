import SwiftUI
import WidgetKit

/// The one widget extension simplyHermes ships (free signing allows few App IDs): the Bots widget
/// for the Home and Lock Screen, and the bot Live Activity with its Dynamic Island.
@main
struct HermesWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BotsWidget()
        BotLiveActivityWidget()
    }
}
