import AppIntents

/// The one screen the Quick Entry intent can open. An `OpenIntent` needs a target; there is only one.
enum QuickEntryScreen: String, AppEnum {
    case quickEntry

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Screen" }

    static var caseDisplayRepresentations: [QuickEntryScreen: DisplayRepresentation] {
        [.quickEntry: "Quick Entry"]
    }
}

/// Opens simplyHermes with the Quick Entry box ready to type in.
///
/// The Action button runs it as an App Shortcut and Control Center runs it from the "Ask Hermes" control. The system
/// brings the app forward to run it, so the sheet opens on arrival. Both entry points go through this one intent.
struct OpenQuickEntryIntent: OpenIntent {
    static var title: LocalizedStringResource { "Open Quick Entry" }
    static var description: IntentDescription { IntentDescription("Opens a box to type a message to Hermes.") }

    @Parameter(title: "Screen", default: .quickEntry)
    var target: QuickEntryScreen

    init() {}

    func perform() async throws -> some IntentResult {
        _ = await AppCommandCenter.shared.perform(.openQuickEntry(prefill: nil))
        return .result()
    }
}
