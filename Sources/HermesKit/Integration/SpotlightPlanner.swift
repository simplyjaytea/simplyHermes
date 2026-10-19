import Foundation

/// A chat the planner may index. It carries a title and a time label and nothing else: message text never
/// reaches Spotlight.
public struct SpotlightChat: Equatable, Sendable {
    public var id: String
    public var title: String
    /// A short time label such as `Yesterday`.
    public var detail: String?

    public init(id: String, title: String, detail: String? = nil) {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

/// A bot the planner may index: its name only.
public struct SpotlightBot: Equatable, Sendable {
    public var name: String
    public var title: String

    public init(name: String, title: String) {
        self.name = name
        self.title = title
    }
}

/// One Spotlight entry.
public struct SpotlightItem: Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case chat
        case bot
    }

    /// The stable id Spotlight keeps the entry under. See ``SpotlightPlanner/target(of:)``.
    public var identifier: String
    public var kind: Kind
    public var title: String
    public var detail: String?
    public var keywords: [String]

    /// Groups entries so one kind can be removed in a single call.
    public var domain: String { kind.rawValue }

    /// Changes whenever anything Spotlight shows changes.
    public var fingerprint: String {
        [kind.rawValue, title, detail ?? "", keywords.joined(separator: ",")].joined(separator: "|")
    }
}

/// Which entries the app has given to Spotlight, so the next update sends only what changed.
public struct SpotlightIndexState: Codable, Equatable, Sendable {
    public static let fileName = "spotlight-index.json"
    /// Bump this when the index name or its protection class changes. Entries saved under another revision were
    /// written to a different index, so they are replaced rather than trusted.
    public static let currentRevision = 1

    /// Entry id to the fingerprint it was indexed with.
    public var fingerprints: [String: String]
    /// The revision the entries were written under. Nil in state saved before revisions existed.
    public var revision: Int?

    public init(fingerprints: [String: String] = [:]) {
        self.fingerprints = fingerprints
        revision = Self.currentRevision
    }

    /// Whether the entries were written to the index this build uses.
    public var isCurrent: Bool { revision == Self.currentRevision }

    public static func store(directory: URL) -> JSONFileStore<SpotlightIndexState> {
        JSONFileStore(directory: directory, fileName: fileName)
    }
}

/// What to send to Spotlight: entries to add or replace, and ids to remove.
public struct SpotlightPlan: Equatable, Sendable {
    public var upserts: [SpotlightItem]
    public var deletions: [String]

    public var isEmpty: Bool { upserts.isEmpty && deletions.isEmpty }
}

/// What a Spotlight result opens.
public enum SpotlightTarget: Equatable, Sendable {
    case chat(String)
    case bot(String)
}

/// Decides what to index in Spotlight (plan: "index sessions and bots, so search finds that chat about the deploy
/// script").
///
/// It indexes chat titles and bot names only, never message bodies. Ids are stable (`chat:<session id>`,
/// `bot:<profile name>`), so a renamed chat replaces its entry and a deleted chat's entry is removed.
public enum SpotlightPlanner {
    public static let chatPrefix = "chat:"
    public static let botPrefix = "bot:"
    /// Chats indexed, newest first.
    public static let maxChats = 500
    public static let maxBots = 50
    /// Longest title kept, in characters.
    public static let maxTitleLength = 120
    /// Titles the app shows before a chat has a real one. Searching for them would find nothing useful.
    public static let placeholderTitles: Set<String> = ["untitled chat", "new chat"]

    public static func identifier(chat id: String) -> String { chatPrefix + id }

    public static func identifier(bot name: String) -> String { botPrefix + name }

    /// What a Spotlight result with this id opens, or `nil` for an id that is not ours.
    public static func target(of identifier: String) -> SpotlightTarget? {
        if identifier.hasPrefix(chatPrefix) {
            let id = String(identifier.dropFirst(chatPrefix.count))
            return id.isEmpty ? nil : .chat(id)
        }
        if identifier.hasPrefix(botPrefix) {
            let name = String(identifier.dropFirst(botPrefix.count))
            return name.isEmpty ? nil : .bot(name)
        }
        return nil
    }

    /// The difference between what should be indexed and what is.
    ///
    /// - Parameters:
    ///   - chats: server chats, newest first. Local placeholder chats do not belong here.
    ///   - bots: the bots of the active server.
    ///   - indexed: what the last update left in Spotlight.
    public static func plan(
        chats: [SpotlightChat], bots: [SpotlightBot], indexed: SpotlightIndexState
    ) -> SpotlightPlan {
        var wanted: [SpotlightItem] = []
        var seen = Set<String>()
        for chat in chats {
            guard wanted.count < maxChats else { break }
            let title = flatten(chat.title)
            guard !title.isEmpty, !placeholderTitles.contains(title.lowercased()), !chat.id.isEmpty else { continue }
            let key = Self.identifier(chat: chat.id)
            guard seen.insert(key).inserted else { continue }
            let detail = chat.detail.map(flatten).flatMap { $0.isEmpty ? nil : $0 }
            wanted.append(
                SpotlightItem(
                    identifier: key, kind: .chat, title: title, detail: detail,
                    keywords: ["simplyHermes", "Hermes", "chat"]))
        }
        for bot in bots.prefix(maxBots) {
            let title = flatten(bot.title.isEmpty ? bot.name : bot.title)
            guard !title.isEmpty, !bot.name.isEmpty else { continue }
            let key = Self.identifier(bot: bot.name)
            guard seen.insert(key).inserted else { continue }
            var keywords = ["simplyHermes", "Hermes", "bot"]
            if title != bot.name { keywords.append(flatten(bot.name)) }
            wanted.append(SpotlightItem(identifier: key, kind: .bot, title: title, detail: "Bot", keywords: keywords))
        }
        let upserts = wanted.filter { indexed.fingerprints[$0.identifier] != $0.fingerprint }
        let deletions = indexed.fingerprints.keys.filter { !seen.contains($0) }.sorted()
        return SpotlightPlan(upserts: upserts, deletions: deletions)
    }

    /// The state after a plan has been sent.
    public static func applying(_ plan: SpotlightPlan, to state: SpotlightIndexState) -> SpotlightIndexState {
        var next = state
        for identifier in plan.deletions { next.fingerprints[identifier] = nil }
        for item in plan.upserts { next.fingerprints[item.identifier] = item.fingerprint }
        return next
    }

    /// One line, no stray spaces, cut to ``maxTitleLength``.
    static func flatten(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > maxTitleLength else { return line }
        return String(line.prefix(maxTitleLength - 1)) + "…"
    }
}
