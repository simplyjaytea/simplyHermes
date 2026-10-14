import ActivityKit
import HermesKit

/// The Live Activity for one running turn or Bot Mode room. Compiled into the app (which starts and
/// updates it) and the widget extension (which draws it).
struct BotActivityAttributes: ActivityAttributes {
    typealias ContentState = LiveTurnState

    var sessionID: String
    var serverName: String
}
