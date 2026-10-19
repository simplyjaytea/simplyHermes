import AppIntents
import HermesKit

/// "New chat": opens simplyHermes on a new chat, and sends a first message when one is given.
struct NewChatIntent: AppIntent {
    static var title: LocalizedStringResource { "New chat" }
    static var description: IntentDescription {
        IntentDescription("Starts a new chat in simplyHermes, with a first message if you give one.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Message", description: "The first message. Leave empty to start with a blank chat.")
    var text: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Start a new chat \(\.$text)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppCommandCenter.shared.perform(IntentMapping.newChat(text: text))
        return .result(dialog: "\(outcome.dialog)")
    }
}
