import AppIntents

/// The shortcuts Siri, Spotlight and the Shortcuts app offer without any setup, and the phrases that start them.
///
/// "Run routine" is not here yet: routines (WP-44) are not built.
struct HermesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskHermesIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
                "Message \(.applicationName)",
            ],
            shortTitle: "Ask Hermes",
            systemImageName: "text.bubble"
        )
        AppShortcut(
            intent: AskBotIntent(),
            phrases: [
                "Ask \(\.$bot) in \(.applicationName)",
                "Message \(\.$bot) in \(.applicationName)",
            ],
            shortTitle: "Ask a bot",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: NewChatIntent(),
            phrases: [
                "Start a new chat in \(.applicationName)",
                "New chat in \(.applicationName)",
            ],
            shortTitle: "New chat",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: StopAllTurnsIntent(),
            phrases: [
                "Stop all turns in \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Stop all turns",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ApprovePendingIntent(),
            phrases: [
                "Approve pending in \(.applicationName)",
                "Approve in \(.applicationName)",
            ],
            shortTitle: "Approve pending",
            systemImageName: "checkmark.circle"
        )
        AppShortcut(
            intent: OpenQuickEntryIntent(),
            phrases: [
                "Open Quick Entry in \(.applicationName)",
                "Quick Entry in \(.applicationName)",
            ],
            shortTitle: "Open Quick Entry",
            systemImageName: "text.cursor"
        )
    }
}
