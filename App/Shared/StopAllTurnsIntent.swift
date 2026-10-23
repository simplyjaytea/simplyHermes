import AppIntents

/// Stops every bot turn that is running.
///
/// A `LiveActivityIntent` runs in the app's process, like the Stop button on the Live Activity, and the main target is
/// asked for explicitly, so the Control Center button reaches the app that holds the connections.
struct StopAllTurnsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Stop all turns" }
    static var description: IntentDescription { IntentDescription("Stops every bot turn that is running.") }
    @available(iOS 27.0, *)
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await AppCommandCenter.shared.perform(.stopAll)
        return .result(dialog: "\(outcome.dialog)")
    }
}
