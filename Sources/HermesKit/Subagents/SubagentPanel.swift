import Foundation

/// Params of `subagent.steer`.
public struct SubagentSteerParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The child to steer.
    public var subagentID: String
    /// The message for the child.
    public var text: String

    /// Creates steer params.
    public init(sessionID: String, subagentID: String, text: String, profile: String? = nil) {
        self.sessionID = sessionID
        self.subagentID = subagentID
        self.text = text
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile, text
        case sessionID = "session_id"
        case subagentID = "subagent_id"
    }
}

/// Params of `subagent.interrupt`.
public struct SubagentInterruptParams: Sendable, Equatable, Codable {
    /// The live session id.
    public var sessionID: String
    /// Profile to scope the call to.
    public var profile: String?
    /// The child to stop.
    public var subagentID: String

    /// Creates interrupt params.
    public init(sessionID: String, subagentID: String, profile: String? = nil) {
        self.sessionID = sessionID
        self.subagentID = subagentID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case sessionID = "session_id"
        case subagentID = "subagent_id"
    }
}

/// Result of `subagent.steer`. `queued` is not delivered: a child past its last tool batch may never read it.
public struct SubagentSteerResult: Sendable, Equatable, Codable {
    /// `queued` or `rejected`.
    public var status: String
    /// The child.
    public var subagentID: String
    /// The message.
    public var text: String

    /// True when the server queued the message for the child.
    public var isQueued: Bool { status == "queued" }

    enum CodingKeys: String, CodingKey {
        case status, text
        case subagentID = "subagent_id"
    }
}

/// Result of `subagent.interrupt`.
public struct SubagentInterruptResult: Sendable, Equatable, Codable {
    /// False when the child had already finished.
    public var found: Bool
    /// The child.
    public var subagentID: String

    enum CodingKeys: String, CodingKey {
        case found
        case subagentID = "subagent_id"
    }
}

extension GatewayClient {
    /// `subagent.list`: the live children and failed delegations of a session.
    public func listSubagents(sessionID: String) async throws -> SubagentListResult {
        try await call("subagent.list", params: SubagentListParams(sessionID: sessionID))
    }

    /// `subagent.steer`: queues a message for a running child.
    public func steerSubagent(_ params: SubagentSteerParams) async throws -> SubagentSteerResult {
        try await call("subagent.steer", params: params)
    }

    /// `subagent.interrupt`: stops a running child.
    public func interruptSubagent(_ params: SubagentInterruptParams) async throws -> SubagentInterruptResult {
        try await call("subagent.interrupt", params: params)
    }
}

/// One row of the subagents panel.
public struct SubagentRow: Sendable, Equatable, Identifiable {
    /// The child's id.
    public var id: String
    /// What it was asked to do.
    public var goal: String
    /// Lifecycle status.
    public var status: SubagentStatus?
    /// Latest activity: the tool in use, else the latest status text.
    public var activity: String?
    /// Nesting depth, where 0 is a direct child.
    public var depth: Int
    /// Seconds running (live) or the final duration (finished). Nil when unknown.
    public var elapsed: Double?
    /// Final summary of a finished child.
    public var summary: String?
    /// True while the child runs or waits to start.
    public var isActive: Bool
    /// True when Steer is offered.
    public var canSteer: Bool
    /// True when Stop is offered.
    public var canStop: Bool
}

/// Builds the rows of the subagents panel from the transcript state and the optional `subagent.list` snapshot.
public enum SubagentPanel {
    /// The panel rows: running children first (oldest first), then finished ones in their original order.
    ///
    /// - Parameters:
    ///   - states: `TranscriptState.subagents`.
    ///   - snapshots: The last `subagent.list` result. It adds the start time and whether a child accepts steering.
    ///   - firstSeen: When this client first saw each child, as the fallback start time.
    ///   - now: The current time.
    public static func rows(
        _ states: [SubagentState], snapshots: [SubagentSnapshot] = [], firstSeen: [String: Date] = [:], now: Date
    ) -> [SubagentRow] {
        let snapshotByID = Dictionary(snapshots.map { ($0.subagentID, $0) }, uniquingKeysWith: { _, last in last })
        let rows = states.map { row($0, snapshotByID[$0.id], firstSeen[$0.id], now) }
        let running = rows.filter(\.isActive)
        return running + rows.filter { !$0.isActive }
    }

    /// How many children are active.
    public static func activeCount(_ states: [SubagentState]) -> Int {
        states.filter { isActive($0.status) }.count
    }

    /// `1:05`, or `1:02:03` after an hour.
    public static func clock(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        let (hours, minutes, secs) = (total / 3600, total % 3600 / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs) : String(format: "%d:%02d", minutes, secs)
    }

    private static func isActive(_ status: SubagentStatus?) -> Bool {
        switch status {
        case nil, .queued?, .running?: true
        default: false
        }
    }

    private static func row(
        _ state: SubagentState, _ snapshot: SubagentSnapshot?, _ seen: Date?, _ now: Date
    ) -> SubagentRow {
        let active = isActive(state.status)
        let elapsed: Double?
        if !active {
            elapsed = state.latest.durationSeconds
        } else if let started = snapshot?.startedAt {
            elapsed = max(0, now.timeIntervalSince1970 - started)
        } else {
            elapsed = seen.map { max(0, now.timeIntervalSince($0)) }
        }
        return SubagentRow(
            id: state.id, goal: state.goal, status: state.status, activity: state.currentTool ?? state.thinking,
            depth: state.latest.depth ?? 0, elapsed: elapsed, summary: state.summary, isActive: active,
            canSteer: active && snapshot?.acceptingSteer != false, canStop: active)
    }
}
