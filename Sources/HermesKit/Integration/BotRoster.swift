import Foundation

/// The bots (Hermes profiles other than the default) of the active server, kept on the phone.
///
/// Siri, Shortcuts and Spotlight need the bot names while the app may not be connected yet, so the app saves them
/// whenever it reads the profile list. The default profile is the plain Hermes chat, not a bot.
public struct BotRoster: Codable, Equatable, Sendable {
    public static let fileName = "bot-roster.json"

    public struct Bot: Codable, Equatable, Sendable, Identifiable {
        /// The profile name. Requests to the server use it.
        public var name: String
        /// The name people say and read: the profile's display name, else its name.
        public var title: String

        public var id: String { name }

        public init(name: String, title: String) {
            self.name = name
            self.title = title
        }
    }

    public var bots: [Bot]
    public var updatedAt: Date

    public init(bots: [Bot], updatedAt: Date) {
        self.bots = bots
        self.updatedAt = updatedAt
    }

    public init(profiles: [HermesProfile], updatedAt: Date) {
        let bots = profiles.filter { $0.isDefault != true }.map { profile in
            let display = profile.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return Bot(name: profile.name, title: display.isEmpty ? profile.name : display)
        }
        self.init(bots: bots, updatedAt: updatedAt)
    }

    /// The bot a spoken or typed name means: its profile name or its title, ignoring case and accents.
    public func bot(named spoken: String) -> Bot? {
        let wanted = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else { return nil }
        return bots.first { Self.same($0.name, wanted) } ?? bots.first { Self.same($0.title, wanted) }
    }

    /// Same bots, ignoring `updatedAt`; used to skip writes that change nothing.
    public func hasSameContent(as other: BotRoster) -> Bool {
        bots == other.bots
    }

    public static func store(directory: URL) -> JSONFileStore<BotRoster> {
        JSONFileStore(directory: directory, fileName: fileName)
    }

    private static func same(_ left: String, _ right: String) -> Bool {
        left.compare(right, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}
