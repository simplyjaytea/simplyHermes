import Foundation

/// The call a room makes. `GatewayClient` conforms; tests use a fake.
public protocol RoomGateway: Sendable {
    func call<Result: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Result.Type, timeout: Double?
    ) async throws -> Result
}

extension GatewayClient: RoomGateway {}

/// The events of a log read, and where the next read starts.
public struct RoomLog: Sendable, Equatable {
    /// Events in sequence order.
    public var events: [RoomEvent]
    /// Where the next read starts (`since_seq`).
    public var cursor: Int
    /// Highest sequence number in the room.
    public var latestSeq: Int
    /// The room's authority when the log was read.
    public var authority: RoomAuthority
}

/// The `groups.*` calls for same-gateway rooms (WP-43). Each call checks what the server would refuse, so a bad id or
/// an empty message fails here, before a round trip.
public struct RoomClient: Sendable {
    /// Events asked for per log page. The server caps a page at `max_log_limit`, which is 500 today.
    public static let logPageLimit = 500
    /// Rooms asked for per list page.
    public static let listPageLimit = 500
    /// Largest message the server takes, in UTF-8 bytes (WP-43 spec, section 2).
    public static let maxMessageBytes = 65_536

    /// The gateway the calls go to.
    public let gateway: any RoomGateway

    /// Creates a client over one gateway.
    public init(gateway: any RoomGateway) {
        self.gateway = gateway
    }

    /// What the gateway can run. A gateway without the room methods cannot host rooms.
    public func capabilities() async throws -> GroupsCapabilitiesResult {
        try await gateway.call(
            "groups.capabilities", params: GroupsCapabilitiesParams(), as: GroupsCapabilitiesResult.self, timeout: nil)
    }

    /// Every active room on the gateway, read page by page.
    public func rooms() async throws -> [Room] {
        var rooms: [Room] = []
        var offset = 0
        while true {
            let page: GroupsListResult = try await gateway.call(
                "groups.list", params: GroupsListParams(limit: Self.listPageLimit, offset: offset),
                as: GroupsListResult.self, timeout: nil)
            rooms += page.rooms
            guard let next = page.nextOffset, next > offset else { return rooms }
            offset = next
        }
    }

    /// Creates a room. Keep `roomID` from before the first try and pass the same one on a retry: the server answers a
    /// repeat with the same room, marked `idempotent`.
    public func create(_ draft: RoomDraft, roomID: String) async throws -> Room {
        try checkRoomID(roomID)
        let problems = draft.problems()
        guard problems.isEmpty else { throw RoomError.invalidDraft(problems) }
        let result: GroupsCreateResult = try await gateway.call(
            "groups.create",
            params: GroupsCreateParams(roomID: roomID, name: draft.effectiveName, members: draft.members),
            as: GroupsCreateResult.self, timeout: nil)
        return result.room
    }

    /// The room with its driver status: whether turns run, and what waits on the user.
    public func state(roomID: String) async throws -> GroupsStateResult {
        try checkRoomID(roomID)
        return try await gateway.call(
            "groups.state", params: GroupsStateParams(roomID: roomID), as: GroupsStateResult.self, timeout: nil)
    }

    /// Every event after `sinceSeq`, read page by page until the server reports no more (WP-43 spec, section 3).
    public func log(roomID: String, since sinceSeq: Int = 0) async throws -> RoomLog {
        try checkRoomID(roomID)
        var events: [RoomEvent] = []
        var cursor = sinceSeq
        while true {
            let page: GroupsLogResult = try await gateway.call(
                "groups.log", params: GroupsLogParams(roomID: roomID, sinceSeq: cursor, limit: Self.logPageLimit),
                as: GroupsLogResult.self, timeout: nil)
            events += page.events
            guard page.hasMore, page.cursor > cursor else {
                return RoomLog(
                    events: events, cursor: page.cursor, latestSeq: page.latestSeq, authority: page.authority)
            }
            cursor = page.cursor
        }
    }

    /// Sends one message as the user. Keep `eventID` from before the first try and pass the same one on a retry, so
    /// the server stores the message once.
    public func send(roomID: String, eventID: String, text: String, threadID: String) async throws -> GroupsSendResult {
        try checkRoomID(roomID)
        try checkIdentifier(eventID)
        try checkIdentifier(threadID)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RoomError.emptyMessage }
        guard trimmed.utf8.count <= Self.maxMessageBytes else { throw RoomError.messageTooLarge }
        guard !RoomMentions.isSlashCommand(trimmed) else { throw RoomError.slashCommand }
        return try await gateway.call(
            "groups.send",
            params: GroupsSendParams(
                roomID: roomID, payload: RoomMessagePayload(text: trimmed, threadID: threadID), eventID: eventID),
            as: GroupsSendResult.self, timeout: nil)
    }

    /// Stops every running turn in the room. `cancelID` names one Stop tap, so send a fresh one per tap.
    public func stop(roomID: String, cancelID: String) async throws -> Int {
        try checkRoomID(roomID)
        try checkIdentifier(cancelID)
        let result: GroupsStopResult = try await gateway.call(
            "groups.stop", params: GroupsStopParams(roomID: roomID, cancelID: cancelID),
            as: GroupsStopResult.self, timeout: nil)
        return result.cancelled
    }

    /// Renames the room. The event id names this rename, so send a fresh one per rename.
    public func rename(roomID: String, eventID: String, to name: String) async throws -> Room {
        try checkRoomID(roomID)
        try checkIdentifier(eventID)
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...RoomDraft.maxNameLength).contains(trimmed.count) else { throw RoomError.invalidName }
        let result: GroupsRenameResult = try await gateway.call(
            "groups.rename", params: GroupsRenameParams(roomID: roomID, eventID: eventID, name: trimmed),
            as: GroupsRenameResult.self, timeout: nil)
        return result.room
    }

    /// Disbands the room. Running turns stop first. A disbanded id is retired for good.
    public func disband(roomID: String, cancelID: String? = nil) async throws -> RoomTombstone {
        try checkRoomID(roomID)
        let result: GroupsDisbandResult = try await gateway.call(
            "groups.disband", params: GroupsDisbandParams(roomID: roomID, cancelID: cancelID),
            as: GroupsDisbandResult.self, timeout: nil)
        return result.tombstone
    }

    /// Answers a member's approval: once, or deny. `action` comes from the room's driver status.
    public func approve(roomID: String, action: RoomPendingAction, choice: RoomApprovalChoice) async throws {
        try checkRoomID(roomID)
        guard let memberID = action.memberID, let executionGeneration = action.executionGeneration,
            let requestID = action.requestID
        else { throw RoomError.staleAction }
        _ = try await gateway.call(
            "groups.approve",
            params: GroupsApproveParams(
                roomID: roomID, memberID: memberID, taskID: action.taskID, executionGeneration: executionGeneration,
                choice: choice, requestID: requestID),
            as: JSONValue.self, timeout: nil)
    }

    /// Runs a task again that the room left indeterminate or deferred. Confirm with the user first.
    public func retry(roomID: String, taskID: String) async throws -> Bool {
        try checkRoomID(roomID)
        try checkIdentifier(taskID)
        let result: GroupsRetryResult = try await gateway.call(
            "groups.retry", params: GroupsRetryParams(roomID: roomID, taskID: taskID),
            as: GroupsRetryResult.self, timeout: nil)
        return result.retried
    }

    private func checkRoomID(_ roomID: String) throws {
        try checkIdentifier(roomID)
    }

    private func checkIdentifier(_ identifier: String) throws {
        guard RoomIdentifier.isValid(identifier) else { throw RoomError.invalidIdentifier(identifier) }
    }
}
