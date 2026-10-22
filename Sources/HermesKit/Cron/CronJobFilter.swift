import Foundation

/// The filter of the Automations list (plan Q37): All, Bots and System. A bot is a named profile, and System is the
/// default profile (``CronJob/botName``). `bot(_:)` narrows the list to one bot's jobs, for the Bots routines pane
/// (WP-44).
public enum CronJobFilter: Sendable, Hashable {
    /// Every job.
    case all
    /// Jobs of a named profile: the bots.
    case bots
    /// Jobs of the default profile.
    case system
    /// One bot's jobs.
    case bot(String)

    /// The chips the Automations tab shows.
    public static let chips: [CronJobFilter] = [.all, .bots, .system]

    /// The chip label. A single bot shows its name.
    public var title: String {
        switch self {
        case .all: "All"
        case .bots: "Bots"
        case .system: "System"
        case .bot(let name): name
        }
    }

    /// Whether `job` is in this filter.
    public func includes(_ job: CronJob) -> Bool {
        switch self {
        case .all: true
        case .bots: job.botName != nil
        case .system: job.botName == nil
        case .bot(let name): job.botName == name
        }
    }
}

/// One section of the list: a bot's jobs, or the System jobs when ``botName`` is nil.
public struct CronJobSection: Sendable, Equatable, Identifiable {
    /// The bot's name, or nil for System.
    public var botName: String?
    /// The jobs in the section, in the order the server sent them.
    public var jobs: [CronJob]

    /// Creates a section.
    public init(botName: String?, jobs: [CronJob]) {
        self.botName = botName
        self.jobs = jobs
    }

    /// Stable identity: the bot's name, or `system`.
    public var id: String { botName.map { "bot:\($0)" } ?? "system" }

    /// The header text.
    public var title: String { botName ?? "System" }
}

/// Groups jobs for the list.
public enum CronJobGrouping {
    /// The sections `filter` shows: one per bot, sorted by name without regard to case, then System.
    public static func sections(_ jobs: [CronJob], filter: CronJobFilter) -> [CronJobSection] {
        let shown = jobs.filter { filter.includes($0) }
        let bots = Set(shown.compactMap(\.botName)).sorted(by: isListedBefore)
        var sections = bots.map { bot in CronJobSection(botName: bot, jobs: shown.filter { $0.botName == bot }) }
        let system = shown.filter { $0.botName == nil }
        if !system.isEmpty {
            sections.append(CronJobSection(botName: nil, jobs: system))
        }
        return sections
    }

    /// The bot names among `jobs`, in the order the sections show them.
    public static func botNames(_ jobs: [CronJob]) -> [String] {
        sections(jobs, filter: .bots).compactMap(\.botName)
    }

    /// Case-insensitive order, with the exact spelling breaking ties so the order never depends on hashing.
    private static func isListedBefore(_ first: String, _ second: String) -> Bool {
        switch first.localizedCaseInsensitiveCompare(second) {
        case .orderedAscending: true
        case .orderedDescending: false
        case .orderedSame: first < second
        }
    }
}
