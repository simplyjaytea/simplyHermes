import AppIntents
import HermesKit

/// A bot (a Hermes profile other than the default) that Siri and Shortcuts can pick. The id is the profile name.
struct BotEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Bot" }
    static let defaultQuery = BotQuery()

    var id: String
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    init(_ bot: BotRoster.Bot) {
        id = bot.name
        title = bot.title
    }
}

/// Finds bots from the roster the app saved last. Siri learns the names through `updateAppShortcutParameters()`.
struct BotQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [BotEntity] {
        let bots = IntentDirectory.roster().bots
        return identifiers.compactMap { id in bots.first { $0.name == id }.map(BotEntity.init) }
    }

    func entities(matching string: String) async throws -> [BotEntity] {
        IntentDirectory.roster().bots
            .filter {
                $0.title.localizedCaseInsensitiveContains(string) || $0.name.localizedCaseInsensitiveContains(string)
            }
            .map(BotEntity.init)
    }

    func suggestedEntities() async throws -> [BotEntity] {
        IntentDirectory.roster().bots.map(BotEntity.init)
    }
}
