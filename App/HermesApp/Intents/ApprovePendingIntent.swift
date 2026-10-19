import AppIntents

/// "Approve pending": approves the command a bot waits on, when exactly one waits.
///
/// With several approvals waiting it does nothing and says so, because approving the wrong command is worse than
/// asking again. It goes through the same action as the Approve button on the Live Activity, and like that button it
/// asks for Face ID or the passcode first.
struct ApprovePendingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Approve pending" }
    static var description: IntentDescription {
        IntentDescription("Approves the command a bot is waiting on, when exactly one command waits.")
    }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppCommandCenter.shared.perform(.approvePending)
        return .result(dialog: "\(outcome.dialog)")
    }
}
