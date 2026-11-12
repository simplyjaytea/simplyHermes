import Foundation

/// What a chat is doing, as the notifications and the Live Activity need it: one shape for server and local chats.
/// Built from the chat's real state (a server chat's transcript, a local chat's snapshot), never from demo flags.
public struct ChatActivity: Sendable, Equatable {
    /// The newest finished reply.
    public struct Reply: Sendable, Equatable {
        public var id: String
        public var text: String

        public init(id: String, text: String) {
            self.id = id
            self.text = text
        }
    }

    public struct Approval: Sendable, Equatable {
        public var id: String
        public var command: String

        public init(id: String, command: String) {
            self.id = id
            self.command = command
        }
    }

    /// A turn is running: the server is replying, or the on-device model is.
    public var isRunning: Bool
    /// The approval the chat waits on, if any.
    public var approval: Approval?
    /// The newest finished reply, if any.
    public var latestReply: Reply?
    /// The last turn ended in an error.
    public var lastTurnFailed: Bool

    public init(isRunning: Bool, approval: Approval? = nil, latestReply: Reply? = nil, lastTurnFailed: Bool = false) {
        self.isRunning = isRunning
        self.approval = approval
        self.latestReply = latestReply
        self.lastTurnFailed = lastTurnFailed
    }

    /// A server chat: running while the transcript has a turn; the newest assistant row that has finished; failed when
    /// that row carries the turn's error.
    public init(transcript: TranscriptState, approval: Approval?) {
        var latest: Reply?
        var failed = false
        for item in transcript.items.reversed() {
            guard case .assistant(let entry) = item.content, entry.displayKind == nil else { continue }
            if !entry.isStreaming {
                latest = Reply(id: item.id, text: entry.text)
                failed = entry.status == .error || entry.error != nil
            }
            break
        }
        self.init(isRunning: transcript.turn != nil, approval: approval, latestReply: latest, lastTurnFailed: failed)
    }

    /// A local chat: running while the on-device model replies; failed when its last reply failed. Local chats have no
    /// approvals.
    public init(local snapshot: LocalChatSnapshot) {
        let reply = snapshot.messages.last { message in
            if case .assistant = message.author { true } else { false }
        }
        self.init(
            isRunning: snapshot.isReplying, approval: nil,
            latestReply: reply.map { Reply(id: "local-reply-\($0.id)", text: $0.text) },
            lastTurnFailed: snapshot.failure != nil)
    }
}

/// Turns changes in each chat's ``ChatActivity`` into ``NotificationEvent``s: a turn that started and ended while
/// the app watched, an approval appearing, an approval going away.
///
/// A turn's reply is only a reply that is new since the turn started, so a turn that fails with no reply never
/// carries the previous turn's text. The turn's id is that reply's row id, which a reconnect replays unchanged, so the
/// planner's dedupe holds across replays. A turn that ended while the app was suspended is never seen running, so it
/// is never announced late.
public struct TurnWatcher: Sendable {
    private struct Running: Sendable {
        var startedAt: Date
        var replyAtStart: String?
    }

    private var running: [String: Running] = [:]
    private var approvals: [String: String] = [:]

    public init() {}

    /// The events for `chat` now. `stoppedByUser` is true when the user stopped this turn (from a widget, the Live
    /// Activity or the chat).
    public mutating func observe(
        _ chat: NotificationChat, _ activity: ChatActivity, stoppedByUser: Bool = false, now: Date
    ) -> [NotificationEvent] {
        var events: [NotificationEvent] = []
        if activity.isRunning {
            if running[chat.id] == nil {
                running[chat.id] = Running(startedAt: now, replyAtStart: activity.latestReply?.id)
            }
        } else if let turn = running.removeValue(forKey: chat.id) {
            let reply = activity.latestReply.flatMap { $0.id == turn.replyAtStart ? nil : $0 }
            let outcome: NotificationEvent.Outcome =
                stoppedByUser ? .stopped : (activity.lastTurnFailed ? .failed : .done)
            let turnID = reply?.id ?? "\(chat.id)@\(Int((turn.startedAt.timeIntervalSince1970 * 1000).rounded()))"
            events.append(
                .turnEnded(
                    chat, turnID: turnID, startedAt: turn.startedAt, endedAt: now, outcome: outcome,
                    reply: reply?.text ?? ""))
        }
        let previous = approvals[chat.id]
        if previous != activity.approval?.id {
            if let previous { events.append(.approvalResolved(chatID: chat.id, requestID: previous)) }
            approvals[chat.id] = activity.approval?.id
            if let approval = activity.approval {
                events.append(.approvalWaiting(chat, requestID: approval.id, command: approval.command))
            }
        }
        return events
    }

    /// How long the running turn of `chatID` has run, or nil when none is.
    public func runningFor(_ chatID: String, now: Date) -> TimeInterval? {
        running[chatID].map { now.timeIntervalSince($0.startedAt) }
    }
}

/// When to offer "Get a notification when Hermes finishes?" in a chat (spec section 4). Never at launch: only after a
/// turn ran longer than ``longTurn`` or reached an approval. "Not now" hides it; it comes back once after three more
/// long turns, and then never. Settings stays the way in.
public struct NotificationOffer: Sendable, Equatable {
    public static let longTurn: TimeInterval = 20
    static let dismissalsKey = "notifications.offer.dismissals"
    static let longTurnsKey = "notifications.offer.longTurnsSinceDismissal"

    public private(set) var dismissals = 0
    public private(set) var longTurnsSinceDismissal = 0

    public init(dismissals: Int = 0, longTurnsSinceDismissal: Int = 0) {
        self.dismissals = dismissals
        self.longTurnsSinceDismissal = longTurnsSinceDismissal
    }

    public static func load(from defaults: UserDefaults) -> NotificationOffer {
        NotificationOffer(
            dismissals: defaults.integer(forKey: dismissalsKey),
            longTurnsSinceDismissal: defaults.integer(forKey: longTurnsKey))
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(dismissals, forKey: Self.dismissalsKey)
        defaults.set(longTurnsSinceDismissal, forKey: Self.longTurnsKey)
    }

    /// A turn ran long or reached an approval. Returns true when the tip should show now. `permissionUndecided` is
    /// true while iOS has not asked yet; after a yes or a no, the tip never shows.
    public mutating func noteLongTurn(permissionUndecided: Bool) -> Bool {
        guard permissionUndecided else { return false }
        switch dismissals {
        case 0:
            return true
        case 1:
            longTurnsSinceDismissal += 1
            return longTurnsSinceDismissal >= 3
        default:
            return false
        }
    }

    /// "Not now".
    public mutating func dismiss() {
        dismissals += 1
        longTurnsSinceDismissal = 0
    }
}
