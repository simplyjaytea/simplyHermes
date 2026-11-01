import Foundation

/// The kinds of room event this app reads. Other kinds produce no row (WP-43 spec, section 3).
public enum RoomEventKind: String, Sendable, Equatable {
    case messageUser = "message.user"
    case messageMember = "message.member"
    case turnSettled = "turn.settled"
    case turnFailed = "turn.failed"
    case turnCancelled = "turn.cancelled"
    case turnDeferred = "turn.deferred"
    case roomActivity = "room.activity"
    case roomStopRequested = "room.stop_requested"
    case roomRenamed = "room.renamed"
    case roomDisbanded = "room.disbanded"
    case authorityClaimed = "authority.claimed"
    case authorityLost = "authority.lost"
}

extension RoomEvent {
    /// The kind, when this app reads it.
    public var knownKind: RoomEventKind? {
        RoomEventKind(rawValue: kind)
    }
}

/// One row of a room transcript (WP-43 spec, section 7). Room-level events become grey activity rows.
public enum RoomRow: Sendable, Equatable, Identifiable {
    case user(seq: Int, text: String, createdAt: Double)
    case member(seq: Int, memberID: String, text: String, threadID: String?, createdAt: Double)
    case activity(seq: Int, text: String)

    public var id: Int {
        switch self {
        case .user(let seq, _, _), .member(let seq, _, _, _, _), .activity(let seq, _):
            return seq
        }
    }
}

/// Turns a room's log into transcript rows.
public enum RoomTimeline {
    /// The name each member shows as: its display name, else its profile, with `default` shown as Hermes.
    public static func labels(for room: Room) -> [String: String] {
        var labels: [String: String] = [:]
        for member in room.members {
            guard let memberID = member.memberID else { continue }
            labels[memberID] = label(for: member)
        }
        return labels
    }

    /// The name one member shows as, the same rule `labels(for:)` uses.
    public static func label(for member: RoomMember) -> String {
        member.displayName ?? profileLabel(member.profile ?? member.memberID ?? "")
    }

    /// The rows for a log, in sequence order.
    public static func rows(from events: [RoomEvent], labels: [String: String] = [:]) -> [RoomRow] {
        events.compactMap { row(for: $0, labels: labels) }
    }

    private static func row(for event: RoomEvent, labels: [String: String]) -> RoomRow? {
        guard let kind = event.knownKind else { return nil }
        let text = event.payload["text"]?.stringValue ?? ""
        switch kind {
        case .messageUser:
            return .user(seq: event.seq, text: text, createdAt: event.createdAt)
        case .messageMember:
            let memberID = event.payload["member_id"]?.stringValue ?? event.actor.id
            return .member(
                seq: event.seq, memberID: memberID, text: text, threadID: event.payload["thread_id"]?.stringValue,
                createdAt: event.createdAt)
        default:
            return activity(for: event, kind: kind, labels: labels).map { .activity(seq: event.seq, text: $0) }
        }
    }

    private static func activity(for event: RoomEvent, kind: RoomEventKind, labels: [String: String]) -> String? {
        let payload = event.payload
        let member = memberLabel(payload["member_id"]?.stringValue, labels: labels)
        switch kind {
        case .turnSettled:
            return payload["passed"]?.boolValue == true ? "\(member) passed" : nil
        case .turnFailed:
            return "\(member) hit an error: \(firstLine(payload["error"]?.stringValue))"
        case .turnCancelled:
            if payload["reason"]?.stringValue == "superseded_by_newer_user_event" {
                return "A newer message interrupted a turn"
            }
            return "A turn was cancelled"
        case .turnDeferred:
            return "A turn is waiting for a free worker"
        case .roomActivity:
            return payload["status"]?.stringValue == "bounded" ? "The turn stopped at its limit" : "The turn settled"
        case .roomStopRequested:
            return "Stop requested"
        case .roomRenamed:
            guard let name = payload["name"]?.stringValue else { return "The room was renamed" }
            return "Renamed to \(name)"
        case .roomDisbanded:
            return "The room was disbanded"
        case .authorityClaimed:
            return "Another gateway took over the room"
        case .authorityLost:
            return "This gateway lost the room"
        case .messageUser, .messageMember:
            return nil
        }
    }

    private static func memberLabel(_ memberID: String?, labels: [String: String]) -> String {
        guard let memberID, !memberID.isEmpty else { return "A bot" }
        return labels[memberID] ?? profileLabel(memberID)
    }

    private static func profileLabel(_ profile: String) -> String {
        profile == "default" ? "Hermes" : profile
    }

    private static func firstLine(_ text: String?) -> String {
        guard let text, let line = text.split(separator: "\n").first else { return "no details" }
        return String(line.prefix(200))
    }
}

/// What a room is doing right now, from its driver status (WP-43 spec, sections 3 and 4).
public enum RoomStatus {
    /// The actions the room waits on. An action that does not decode is left out.
    public static func pendingActions(in status: RoomDriverStatus?) -> [RoomPendingAction] {
        (status?.pendingActions ?? []).compactMap { try? $0.decode(RoomPendingAction.self) }
    }

    /// The first approval the room waits on, which the banner offers to answer.
    public static func pendingApproval(in status: RoomDriverStatus?) -> RoomPendingAction? {
        pendingActions(in: status).first { $0.kind == "approval" }
    }

    /// The line under the transcript. Nil when the room is idle.
    public static func line(for status: RoomDriverStatus?) -> String? {
        if pendingApproval(in: status) != nil { return "Waiting for your answer…" }
        if status?.working == true { return "The room is working…" }
        if status?.blocked == true { return "The room needs attention" }
        return nil
    }

    /// How often the Bots roster polls room driver statuses while visible (5 seconds).
    public static let listPollInterval: TimeInterval = 5

    /// Whether a room waits on the user based on its driver status (an approval is pending).
    public static func needsAttention(status: RoomDriverStatus?) -> Bool {
        pendingApproval(in: status) != nil
    }

    /// Whether a room waits on the user given the dictionary of polled room driver statuses.
    public static func needsAttention(roomID: String, in statuses: [String: RoomDriverStatus]) -> Bool {
        needsAttention(status: statuses[roomID])
    }

    /// Stop shows while the room runs or is blocked. The server keeps no hold state to show.
    public static func showsStop(_ status: RoomDriverStatus?) -> Bool {
        status?.working == true || status?.blocked == true
    }
}

/// The outcome of sending a message in a group chat (WP-43 spec, section 3).
public struct RoomSendOutcome: Sendable, Equatable {
    /// Whether the user's typed draft should be cleared from the composer.
    public var shouldClearDraft: Bool
    /// Whether the queued outgoing message record (and its idempotency IDs) should be cleared.
    public var shouldClearOutgoing: Bool
    /// The user-visible error or warning message to surface, if any.
    public var actionError: String?

    public init(shouldClearDraft: Bool, shouldClearOutgoing: Bool, actionError: String? = nil) {
        self.shouldClearDraft = shouldClearDraft
        self.shouldClearOutgoing = shouldClearOutgoing
        self.actionError = actionError
    }

    /// Evaluates the outcome of a `groups.send` RPC result.
    public static func evaluate(result: GroupsSendResult) -> RoomSendOutcome {
        if result.accepted {
            return RoomSendOutcome(
                shouldClearDraft: true,
                shouldClearOutgoing: true,
                actionError: result.driverStarted ? nil : "Message saved; the room did not start a turn."
            )
        } else {
            // Keep the draft and outgoing IDs, so trying again reuses the same message.
            return RoomSendOutcome(
                shouldClearDraft: false,
                shouldClearOutgoing: false,
                actionError: "The room did not accept the message. Try again."
            )
        }
    }

    /// Determines the outgoing message for a send attempt.
    /// When retrying with the same draft text as a pending message that was not cleared by an earlier outcome,
    /// the pending message is preserved so its `eventID` and `threadID` are reused on retry.
    public static func nextOutgoing(
        for draft: String,
        pending: RoomOutgoingMessage?,
        previousOutcome: RoomSendOutcome? = nil
    ) -> RoomOutgoingMessage? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let previousOutcome, previousOutcome.shouldClearOutgoing {
            return RoomOutgoingMessage(text: trimmed)
        }
        if let pending, pending.text == trimmed {
            return pending
        }
        return RoomOutgoingMessage(text: trimmed)
    }

    /// Evaluates the pending outgoing message to hold after evaluating `outcome`.
    /// When `shouldClearOutgoing == false`, the current outgoing message (and its eventID) is retained for retry.
    /// When `shouldClearOutgoing == true`, the outgoing message is cleared (returns nil).
    public static func retainedOutgoing(
        current: RoomOutgoingMessage?,
        outcome: RoomSendOutcome
    ) -> RoomOutgoingMessage? {
        outcome.shouldClearOutgoing ? nil : current
    }
}

/// Pure presentation logic for the Group Chats roster section (WP-43 spec, section 1).
public enum RoomsListPresentation {
    /// What the section displays when there are no visible rooms.
    public enum EmptyState: Sendable, Equatable {
        /// Shows the "New Group" action button.
        case createAction
        /// Shows the explanation text that two ready bots are needed.
        case explanation(String)
    }

    /// Determines the empty state to display when `visibleRooms` is empty.
    public static func emptyState(canCreate: Bool) -> EmptyState {
        if canCreate {
            return .createAction
        }
        return .explanation("Two ready bots are needed to make a group.")
    }
}
