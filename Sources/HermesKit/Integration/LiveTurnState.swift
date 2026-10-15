import Foundation

/// What the Live Activity and Dynamic Island show for one running turn or Bot Mode room.
///
/// This is the ActivityKit content state (the app wraps it in `BotActivityAttributes`), so it stays
/// small: ActivityKit rejects updates over 4 KB. Long text is cut when the state is built.
public struct LiveTurnState: Codable, Hashable, Sendable {
    public enum Phase: String, Codable, Hashable, Sendable, CaseIterable {
        case thinking
        case runningTool
        case waitingForApproval
        case done
        case failed
        case stopped

        /// The turn is over; the activity shows its final state, then ends.
        public var isFinished: Bool {
            switch self {
            case .done, .failed, .stopped: true
            case .thinking, .runningTool, .waitingForApproval: false
            }
        }
    }

    /// Longest `lastLine` kept, in characters.
    public static let lastLineLimit = 160
    /// Longest `pendingCommand` kept, in characters.
    public static let commandLimit = 300
    /// ActivityKit's limit for one update.
    public static let maximumEncodedSize = 4096

    public var phase: Phase
    /// The bot (or "Hermes" for a plain chat) that is working.
    public var botName: String
    /// The chat title.
    public var title: String
    /// The end of the last line of output, or the tool that is running.
    public var lastLine: String
    /// The command waiting for approval, when `phase` is `.waitingForApproval`.
    public var pendingCommand: String?
    public var startedAt: Date
    /// Bots working in this room; above 1 the activity reads "3 bots working".
    public var activeBotCount: Int

    public init(
        phase: Phase,
        botName: String,
        title: String,
        lastLine: String,
        pendingCommand: String? = nil,
        startedAt: Date,
        activeBotCount: Int = 1
    ) {
        self.phase = phase
        self.botName = botName
        self.title = title
        self.lastLine = Self.cutKeepingEnd(Self.singleLine(lastLine), to: Self.lastLineLimit)
        self.pendingCommand = pendingCommand.map { Self.cut($0, to: Self.commandLimit) }
        self.startedAt = startedAt
        self.activeBotCount = max(1, activeBotCount)
    }

    /// Whether the Approve and Deny buttons apply.
    public var needsApproval: Bool {
        phase == .waitingForApproval && pendingCommand != nil
    }

    /// The JSON size ActivityKit sees.
    public func encodedSize() throws -> Int {
        try JSONEncoder().encode(self).count
    }

    /// Keeps the last line of multi-line output, since that is what is happening now.
    static func singleLine(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.last { !$0.isEmpty } ?? ""
    }

    static func cut(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return String(text.prefix(limit - 1)) + "…"
    }

    /// Streaming output grows at the end, so the end is what to keep.
    static func cutKeepingEnd(_ text: String, to limit: Int) -> String {
        guard text.count > limit else { return text }
        return "…" + String(text.suffix(limit - 1))
    }
}

/// The fixed part of a Live Activity: which chat it belongs to.
public struct LiveTurnAttributes: Codable, Hashable, Sendable {
    public var sessionID: String
    public var serverName: String

    public init(sessionID: String, serverName: String) {
        self.sessionID = sessionID
        self.serverName = serverName
    }
}

/// Decides when a Live Activity update goes out, so streaming tokens never flood ActivityKit.
///
/// Phase changes and a new pending command go out at once. Anything else goes out at most once per
/// `minimumInterval`; an update that arrives sooner is held and the newest held state is sent when the
/// interval ends.
public struct LiveUpdateThrottle: Sendable {
    public enum Decision: Equatable, Sendable {
        case sendNow
        case sendAt(Date)
    }

    public let minimumInterval: TimeInterval
    private var lastSentAt: Date?
    private var lastSent: LiveTurnState?

    public init(minimumInterval: TimeInterval = 1) {
        self.minimumInterval = minimumInterval
    }

    public func decide(_ state: LiveTurnState, now: Date) -> Decision {
        guard let lastSentAt, let lastSent else { return .sendNow }
        if state.phase != lastSent.phase || state.pendingCommand != lastSent.pendingCommand {
            return .sendNow
        }
        let due = lastSentAt.addingTimeInterval(minimumInterval)
        return now >= due ? .sendNow : .sendAt(due)
    }

    public mutating func markSent(_ state: LiveTurnState, at date: Date) {
        lastSent = state
        lastSentAt = date
    }
}

/// A button on the Live Activity, Dynamic Island or a widget.
public enum LiveTurnAction: String, Codable, Hashable, Sendable, CaseIterable {
    case stop
    case deny
    case approve

    /// The buttons a state offers, in the order of the tent glance view: Stop, Deny, Approve.
    public static func available(for state: LiveTurnState) -> [LiveTurnAction] {
        if state.phase.isFinished { return [] }
        return state.needsApproval ? [.stop, .deny, .approve] : [.stop]
    }
}
