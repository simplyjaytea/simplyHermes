import Foundation

/// The answer to an approval a room member asks for: run once, or deny (WP-43 spec, section 3).
public enum RoomApprovalChoice: String, Sendable, Equatable, Codable {
    case once
    case deny
}

/// One action a room waits on, read from the driver status: a retry, or a member's approval.
public struct RoomPendingAction: Sendable, Equatable, Codable {
    /// `retry` or `approval`.
    public var kind: String
    /// Task the action belongs to.
    public var taskID: String
    /// Member the task runs for, for an approval.
    public var memberID: String?
    /// Execution generation the approval was asked under.
    public var executionGeneration: Int?
    /// Id of the approval request.
    public var requestID: String?
    /// The approval being asked for, when the action is an approval.
    public var approval: RoomApproval?

    enum CodingKeys: String, CodingKey {
        case kind
        case taskID = "task_id"
        case memberID = "member_id"
        case executionGeneration = "execution_generation"
        case requestID = "request_id"
        case approval
    }
}

/// What a pending approval offers, and the command it is for, when the server sends one.
public struct RoomApproval: Sendable, Equatable, Codable {
    /// The answers the server accepts, such as `once` and `deny`.
    public var choices: [String]?
    /// The command the member wants to run, when the server names it.
    public var command: String?
}

/// Params of `groups.approve`. Every field must match the pending action, or the server answers that it is no
/// longer pending (WP-43 spec, section 3).
public struct GroupsApproveParams: Sendable, Equatable, Codable {
    /// Room the action belongs to.
    public var roomID: String
    /// Member that asked.
    public var memberID: String
    /// Task that is waiting.
    public var taskID: String
    /// Execution generation of the pending approval.
    public var executionGeneration: Int
    /// The answer.
    public var choice: RoomApprovalChoice
    /// Id of the approval request.
    public var requestID: String

    /// Creates an approve request.
    public init(
        roomID: String, memberID: String, taskID: String, executionGeneration: Int, choice: RoomApprovalChoice,
        requestID: String
    ) {
        self.roomID = roomID
        self.memberID = memberID
        self.taskID = taskID
        self.executionGeneration = executionGeneration
        self.choice = choice
        self.requestID = requestID
    }

    enum CodingKeys: String, CodingKey {
        case choice
        case roomID = "room_id"
        case memberID = "member_id"
        case taskID = "task_id"
        case executionGeneration = "execution_generation"
        case requestID = "request_id"
    }
}

/// Params of `groups.retry`: run a task again that the room left indeterminate or deferred.
public struct GroupsRetryParams: Sendable, Equatable, Codable {
    /// Room the task belongs to.
    public var roomID: String
    /// Task to run again.
    public var taskID: String

    /// Creates a retry request.
    public init(roomID: String, taskID: String) {
        self.roomID = roomID
        self.taskID = taskID
    }

    enum CodingKeys: String, CodingKey {
        case roomID = "room_id"
        case taskID = "task_id"
    }
}

/// Result of `groups.retry`.
public struct GroupsRetryResult: Sendable, Equatable, Codable {
    /// True when the task was queued again.
    public var retried: Bool
}
