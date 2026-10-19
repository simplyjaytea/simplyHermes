import Foundation

/// One bot as a gateway reported it: rich fields from its WebSocket `profiles.list`, or thin fields from REST `/api/profiles`.
public struct BotRosterRow: Sendable, Equatable {
    public var profile: String
    public var isDefault: Bool
    /// Bot Mode title the backend reports (`ui_meta["hermes-bots"].title`, or REST `bot_title`).
    public var backendTitle: String?
    public var displayName: String?
    public var description: String?
    public var model: String?
    public var provider: String?
    /// The `hermes-bots` namespace. Empty for thin REST rows, so their hidden and pinned state is unknown until a rich read.
    public var meta: BotMetaObject
    /// The `simplyhermes` namespace: this app's avatar. Empty for thin rows.
    public var appLook: BotAppLook
    /// The live tip of the Bot Chat (`canonical_session.resolved_id`, else `id`), when the gateway reports one.
    public var canonicalSessionID: String?
    /// Unix seconds of the newest activity, from the fresher of the Bot Chat and the last session.
    public var lastActive: Double?
    /// Unix seconds of the newest worker (kanban or tool) activity.
    public var workerActiveAt: Double?
    /// The newest user or assistant text in the Bot Chat, at most 80 characters.
    public var preview: String?

    public init(
        profile: String, isDefault: Bool = false, backendTitle: String? = nil, displayName: String? = nil,
        description: String? = nil, model: String? = nil, provider: String? = nil,
        meta: BotMetaObject = BotMetaObject(),
        appLook: BotAppLook = BotAppLook(avatar: nil), canonicalSessionID: String? = nil, lastActive: Double? = nil,
        workerActiveAt: Double? = nil, preview: String? = nil
    ) {
        self.profile = profile
        self.isDefault = isDefault
        self.backendTitle = backendTitle
        self.displayName = displayName
        self.description = description
        self.model = model
        self.provider = provider
        self.meta = meta
        self.appLook = appLook
        self.canonicalSessionID = canonicalSessionID
        self.lastActive = lastActive
        self.workerActiveAt = workerActiveAt
        self.preview = preview
    }
}

/// One gateway's answer for the roster: its rows, and whether they came from a live read.
public struct BotRosterSource: Sendable, Equatable {
    public var connectionID: UUID
    /// The connection's name: the gateway header and the `-label` in a clashing handle.
    public var label: String
    public var isPrimary: Bool
    /// Lower wins when two gateways list the same install: local 0, ssh 1, remote 2, cloud 3.
    public var priority: Int
    /// `install_id`. Nil when unknown, so rows are never merged across gateways.
    public var installID: String?
    /// False when the last read failed. Rows from the previous read then stay, marked retained.
    public var reachable: Bool
    /// True for the active gateway's WebSocket rows, false for REST rows from the others.
    public var isRich: Bool
    public var rows: [BotRosterRow]

    public init(
        connectionID: UUID, label: String, isPrimary: Bool = false, priority: Int = 0, installID: String? = nil,
        reachable: Bool = true, isRich: Bool = false, rows: [BotRosterRow]
    ) {
        self.connectionID = connectionID
        self.label = label
        self.isPrimary = isPrimary
        self.priority = priority
        self.installID = installID
        self.reachable = reachable
        self.isRich = isRich
        self.rows = rows
    }
}

/// What a roster row can do right now.
public enum BotRosterStatus: Sendable, Equatable {
    /// Rich and reachable: chat, activity and preview are live.
    case ready
    /// Listed over REST but not connected. Opening it connects on demand.
    case onDemand
    /// The gateway did not answer. A row from the last read stays, marked retained.
    case unavailable
}

/// A bot on the roster, ready to draw.
public struct BotRosterEntry: Identifiable, Sendable, Equatable {
    public var id: String { "\(connectionID.uuidString)::\(profile)" }
    public let connectionID: UUID
    public let sourceLabel: String
    public let profile: String
    /// The name after `@`. `default` is shown as `hermes` by ``mention``.
    public let handle: String
    public let title: String
    public let monogram: String
    public let tint: String
    public let avatar: BotAvatar?
    public let status: BotRosterStatus
    public let isRetained: Bool
    public let isPinned: Bool
    public let isHidden: Bool
    public let isDefault: Bool
    public let role: String?
    public let preview: String?
    public let lastActive: Double?
    public let workerActiveAt: Double?
    public let canonicalSessionID: String?
    /// Sort key in milliseconds: the newer of creation and last activity.
    public let activity: Double

    public var mention: String { BotNaming.mentionHandle(handle) }
}

/// Activity of a bot right now, for the "Active now" line and the working dot.
public enum BotActivity: Sendable, Equatable {
    case idle
    /// A turn runs, or the bot spoke in the last 90 seconds.
    case active
    /// A worker ran in the last 150 seconds.
    case working
}

/// Builds the bot roster across every connection (plan 2.5, WP-42).
public enum BotRoster {
    /// Seconds for "active now" after a turn or message.
    public static let activeWindow: Double = 90
    /// Seconds for "working" after a worker.
    public static let workingWindow: Double = 150
    /// Seconds in the "recent" filter, seven days.
    public static let recentWindow: Double = 7 * 24 * 3600

    /// Every bot, once per install and profile. Handles are the profile name, or `profile-label` when two gateways
    /// both have that profile name. Pinned bots lead, then the newest activity.
    public static func entries(_ sources: [BotRosterSource]) -> [BotRosterEntry] {
        let candidates = collapse(sources)
        var counts: [String: Int] = [:]
        for candidate in candidates {
            counts[candidate.row.profile, default: 0] += 1
        }
        let entries = candidates.map { candidate -> BotRosterEntry in
            let source = candidate.source
            let row = candidate.row
            let handle =
                (counts[row.profile] ?? 0) > 1
                ? row.profile + "-" + BotNaming.labelSlug(source.label)
                : row.profile
            let title = BotNaming.displayName(
                profile: row.profile, title: row.meta.title ?? row.backendTitle, displayName: row.displayName)
            let status: BotRosterStatus =
                !source.reachable ? .unavailable : (source.isRich ? .ready : .onDemand)
            let activeMillis = max(Double(row.meta.createdAt ?? 0), (row.lastActive ?? 0) * 1000)
            return BotRosterEntry(
                connectionID: source.connectionID, sourceLabel: source.label, profile: row.profile, handle: handle,
                title: title, monogram: BotMonogram.text(for: title), tint: BotTint.name(for: row.profile),
                avatar: row.appLook.avatar, status: status, isRetained: !source.reachable,
                isPinned: row.meta.pinned, isHidden: row.meta.hidden, isDefault: row.isDefault,
                role: row.description, preview: row.preview, lastActive: row.lastActive,
                workerActiveAt: row.workerActiveAt, canonicalSessionID: row.canonicalSessionID,
                activity: activeMillis)
        }
        return zip(candidates, entries).enumerated()
            .sorted { lhs, rhs in
                let (left, right) = (lhs.element.1, rhs.element.1)
                if left.isPinned != right.isPinned { return left.isPinned }
                if left.activity != right.activity { return left.activity > right.activity }
                return lhs.offset < rhs.offset
            }
            .map(\.element.1)
    }

    /// The roster as sections, the way the list draws it: one section per gateway when there are two or more, hidden
    /// bots last. A search shows hidden bots too and keeps the roster order.
    public static func sections(
        _ entries: [BotRosterEntry], sources: [BotRosterSource], query: String = ""
    ) -> [BotRosterSection] {
        let needle = normalizedQuery(query)
        let matching = needle.isEmpty ? entries : entries.filter { matches($0, needle: needle) }
        if !needle.isEmpty {
            return grouped(matching, sources: sources)
        }
        let visible = matching.filter { !$0.isHidden }
        let hidden = matching.filter { $0.isHidden }
        var result = grouped(visible, sources: sources)
        if !hidden.isEmpty {
            result.append(BotRosterSection(id: "hidden", title: "Hidden", entries: hidden))
        }
        return result
    }

    /// True when the entry matches a search. The needle is already normalized by ``normalizedQuery(_:)``.
    public static func matches(_ entry: BotRosterEntry, needle: String) -> Bool {
        let fields = [
            entry.title, entry.profile, entry.handle, entry.sourceLabel, entry.role ?? "", entry.preview ?? "",
        ]
        return fields.contains { $0.lowercased().contains(needle) }
    }

    /// Trims, lowercases and drops one leading `@`.
    public static func normalizedQuery(_ query: String) -> String {
        var text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("@") { text.removeFirst() }
        return text
    }

    /// Activity of one bot. `runningTurn` is true while a turn of this bot runs on any surface.
    public static func activity(
        lastActive: Double?, workerActiveAt: Double?, runningTurn: Bool, now: Double
    ) -> BotActivity {
        if let workerActiveAt, now - workerActiveAt < workingWindow { return .working }
        if runningTurn { return .active }
        if let lastActive, now - lastActive < activeWindow { return .active }
        return .idle
    }

    /// True when the bot was active within the last seven days.
    public static func isRecent(lastActive: Double?, now: Double) -> Bool {
        guard let lastActive else { return false }
        return now - lastActive < recentWindow
    }

    // MARK: Private

    private struct Candidate {
        let source: BotRosterSource
        let row: BotRosterRow
        let order: Int
    }

    /// Keeps one row per install and profile. The primary gateway wins, then the lower priority, then registry order.
    private static func collapse(_ sources: [BotRosterSource]) -> [Candidate] {
        let ranked = sources.enumerated().sorted { lhs, rhs in
            if lhs.element.isPrimary != rhs.element.isPrimary { return lhs.element.isPrimary }
            if lhs.element.priority != rhs.element.priority { return lhs.element.priority < rhs.element.priority }
            return lhs.offset < rhs.offset
        }
        var seen: Set<String> = []
        var candidates: [Candidate] = []
        for (sourceIndex, source) in ranked {
            for (rowIndex, row) in source.rows.enumerated() {
                if let installID = source.installID, !seen.insert(installID + "::" + row.profile).inserted {
                    continue
                }
                candidates.append(Candidate(source: source, row: row, order: sourceIndex * 100_000 + rowIndex))
            }
        }
        return candidates.sorted { $0.order < $1.order }
    }

    private static func grouped(_ entries: [BotRosterEntry], sources: [BotRosterSource]) -> [BotRosterSection] {
        guard sources.count > 1 else {
            return entries.isEmpty ? [] : [BotRosterSection(id: "all", title: "", entries: entries)]
        }
        let ordered = sources.sorted {
            $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending
        }
        return ordered.compactMap { source -> BotRosterSection? in
            let rows = entries.filter { $0.connectionID == source.connectionID }
            guard !rows.isEmpty else { return nil }
            return BotRosterSection(id: source.connectionID.uuidString, title: source.label, entries: rows)
        }
    }
}

/// A group of roster rows drawn under one header.
public struct BotRosterSection: Identifiable, Sendable, Equatable {
    public let id: String
    /// The gateway's name, or `Hidden`, or empty for a flat list.
    public let title: String
    public let entries: [BotRosterEntry]
}
