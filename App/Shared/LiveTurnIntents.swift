import AppIntents
import HermesKit

/// Runs Stop, Deny and Approve from the Live Activity, Dynamic Island and widgets.
///
/// The intents are `LiveActivityIntent`s, so iOS runs them in the app's process (launching it in the
/// background if needed) even when the button sits in the widget extension. The app registers the
/// handler at launch. This also works without an App Group, which is the fallback when SideStore drops it.
@MainActor
final class LiveTurnActionCenter {
    static let shared = LiveTurnActionCenter()

    var handler: (@MainActor (LiveTurnAction, String) -> Void)?

    func perform(_ action: LiveTurnAction, sessionID: String) {
        handler?(action, sessionID)
    }
}

struct StopTurnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop" }
    static var description: IntentDescription { IntentDescription("Stops a bot's running turn.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Chat")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        await LiveTurnActionCenter.shared.perform(.stop, sessionID: sessionID)
        return .result()
    }
}

struct DenyTurnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Deny" }
    static var description: IntentDescription { IntentDescription("Denies the command a bot is waiting on.") }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Chat")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        await LiveTurnActionCenter.shared.perform(.deny, sessionID: sessionID)
        return .result()
    }
}

/// Approve runs the bot's command, so it asks for Face ID on a locked phone.
struct ApproveTurnIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Approve" }
    static var description: IntentDescription { IntentDescription("Approves the command a bot is waiting on.") }
    static var isDiscoverable: Bool { false }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }

    @Parameter(title: "Chat")
    var sessionID: String

    init() {}

    init(sessionID: String) {
        self.sessionID = sessionID
    }

    func perform() async throws -> some IntentResult {
        await LiveTurnActionCenter.shared.perform(.approve, sessionID: sessionID)
        return .result()
    }
}
