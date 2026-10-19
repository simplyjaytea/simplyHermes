import AppIntents
import HermesKit

/// "Ask Hermes": sends a message to a chat and opens simplyHermes.
///
/// With no chat chosen the message follows up in the chat used last. The intent runs in the app, which holds the
/// connection; it only queues the message, and the app delivers it as soon as the chat is ready.
struct AskHermesIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask Hermes" }
    static var description: IntentDescription {
        IntentDescription("Sends a message to a chat and opens simplyHermes.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Message", requestValueDialog: "What do you want to ask Hermes?")
    var text: String

    @Parameter(title: "Chat", description: "Leave empty to use the chat you used last.")
    var chat: ChatEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Hermes \(\.$text) in \(\.$chat)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let request: IntentRequest
        do {
            request = try IntentMapping.ask(text: text, chatID: chat?.id)
        } catch {
            return .result(dialog: "\(IntentMappingError.dialog(for: error))")
        }
        let outcome = await AppCommandCenter.shared.perform(request)
        return .result(dialog: "\(outcome.dialog)")
    }
}
