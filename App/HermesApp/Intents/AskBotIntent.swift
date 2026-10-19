import AppIntents
import HermesKit

/// "Ask a bot": starts a new chat that works as the chosen bot and sends the message there.
///
/// A bot is a Hermes profile other than the default one.
struct AskBotIntent: AppIntent {
    static var title: LocalizedStringResource { "Ask a bot" }
    static var description: IntentDescription {
        IntentDescription("Starts a new chat with one of your bots and sends a message.")
    }
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Bot")
    var bot: BotEntity

    @Parameter(title: "Message", requestValueDialog: "What do you want to ask?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$bot) \(\.$text)")
    }

    init() {}

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let request: IntentRequest
        do {
            request = try IntentMapping.askBot(bot: bot.id, text: text)
        } catch {
            return .result(dialog: "\(IntentMappingError.dialog(for: error))")
        }
        let outcome = await AppCommandCenter.shared.perform(request)
        return .result(dialog: "\(outcome.dialog)")
    }
}
