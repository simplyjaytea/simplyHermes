/// A member of a group room. The same shape is used for input (`groups.create`) and output.
public struct RoomMember: Sendable, Equatable, Codable {
    /// Member id within the room.
    public var memberID: String?
    /// Profile that runs the member.
    public var profile: String?
    /// Handle used for @-mentions.
    public var handle: String?
    /// Display name.
    public var displayName: String?
    /// Where the member runs. Kept raw, for example `{"kind":"local","profile":"ops"}`.
    public var target: JSONValue?

    /// Creates a member.
    public init(
        memberID: String? = nil, profile: String? = nil, handle: String? = nil, displayName: String? = nil,
        target: JSONValue? = nil
    ) {
        self.memberID = memberID
        self.profile = profile
        self.handle = handle
        self.displayName = displayName
        self.target = target
    }

    enum CodingKeys: String, CodingKey {
        case profile, handle, target
        case memberID = "member_id"
        case displayName = "display_name"
    }
}

/// Who wrote a room event.
public struct RoomActor: Sendable, Equatable, Codable {
    /// `user`, `member` or `system`.
    public var kind: String
    /// Id of the actor.
    public var id: String
    /// Profile of a member actor, when set.
    public var profile: String?
}

/// One event in a room's log. `seq` orders events within a room.
public struct RoomEvent: Sendable, Equatable, Codable {
    /// Room the event belongs to.
    public var roomID: String
    /// Position of the event in the room's log.
    public var seq: Int
    /// Idempotency key of the event.
    public var eventID: String
    /// Event kind, such as `message.user` or `message.member`.
    public var kind: String
    /// Who wrote it.
    public var actor: RoomActor
    /// Authority epoch the event was written under.
    public var authorityEpoch: Int?
    /// Event payload. Kept raw; its shape depends on `kind`.
    public var payload: JSONValue
    /// When it was written (Unix seconds).
    public var createdAt: Double
    /// True when the write was a duplicate of an earlier one.
    public var idempotent: Bool?

    enum CodingKeys: String, CodingKey {
        case seq, kind, actor, payload, idempotent
        case roomID = "room_id"
        case eventID = "event_id"
        case authorityEpoch = "authority_epoch"
        case createdAt = "created_at"
    }
}

/// The gateway that owns a room's writes, and its epoch.
public struct RoomAuthority: Sendable, Equatable, Codable {
    /// Id of the owning gateway.
    public var gatewayID: String
    /// Authority epoch. It goes up when ownership moves.
    public var epoch: Int

    enum CodingKeys: String, CodingKey {
        case epoch
        case gatewayID = "gateway_id"
    }
}

/// A group room.
public struct Room: Sendable, Equatable, Codable {
    /// Room id.
    public var roomID: String
    /// Room name.
    public var name: String
    /// Members.
    public var members: [RoomMember]
    /// Gateway that owns the room's writes.
    public var authorityGatewayID: String
    /// Authority epoch.
    public var authorityEpoch: Int
    /// Revision of the room record.
    public var revision: Int
    /// When the room was created (Unix seconds).
    public var createdAt: Double
    /// When the room was last changed (Unix seconds).
    public var updatedAt: Double
    /// True when the create was a duplicate.
    public var idempotent: Bool?
    /// When the room was disbanded (Unix seconds), if it was.
    public var disbandedAt: Double?
    /// Highest event sequence number.
    public var latestSeq: Int?
    /// True when the room was adopted from another gateway.
    public var adopted: Bool?
    /// The claim event, when the room was adopted.
    public var claimEvent: RoomEvent?
    /// The authority claim event, when set.
    public var authorityClaim: RoomEvent?
    /// The event that came with the result, when any.
    public var event: RoomEvent?

    enum CodingKeys: String, CodingKey {
        case name, members, revision, idempotent, adopted, event
        case roomID = "room_id"
        case authorityGatewayID = "authority_gateway_id"
        case authorityEpoch = "authority_epoch"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case disbandedAt = "disbanded_at"
        case latestSeq = "latest_seq"
        case claimEvent = "claim_event"
        case authorityClaim = "authority_claim"
    }
}

/// Driver state of a room: whether turns are running.
public struct RoomDriverStatus: Sendable, Equatable, Codable {
    /// True while the driver runs.
    public var running: Bool
    /// True while a member is working.
    public var working: Bool
    /// True when the room is blocked.
    public var blocked: Bool
    /// Counts by category.
    public var counts: [String: Int]
    /// Queued actions. Kept raw.
    public var pendingActions: [JSONValue]
    /// Routes to peer gateways. Kept raw.
    public var peerRoutes: [JSONValue]

    enum CodingKeys: String, CodingKey {
        case running, working, blocked, counts
        case pendingActions = "pending_actions"
        case peerRoutes = "peer_routes"
    }
}

/// What remains of a disbanded room.
public struct RoomTombstone: Sendable, Equatable, Codable {
    /// Room id.
    public var roomID: String
    /// When it was disbanded (Unix seconds).
    public var disbandedAt: Double
    /// True when the disband was a duplicate.
    public var idempotent: Bool
    /// True when the history has expired.
    public var historyExpired: Bool?
    /// The disband event.
    public var event: RoomEvent?

    enum CodingKeys: String, CodingKey {
        case idempotent, event
        case roomID = "room_id"
        case disbandedAt = "disbanded_at"
        case historyExpired = "history_expired"
    }
}

/// Params of `groups.capabilities`.
public struct GroupsCapabilitiesParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?

    /// Creates the params.
    public init(profile: String? = nil) {
        self.profile = profile
    }
}

/// Result of `groups.capabilities`.
public struct GroupsCapabilitiesResult: Sendable, Equatable, Codable {
    /// Protocol version of the rooms feature.
    public var protocolVersion: Int
    /// True when this gateway runs room turns.
    public var driver: Bool
    /// True when the room process survives client disconnects.
    public var persistentProcess: Bool
    /// Gateway that owns room writes.
    public var authorityGatewayID: String
    /// Link status to other gateways. Kept raw.
    public var roomLink: JSONValue
    /// Feature names.
    public var features: [String]
    /// Method names the rooms feature supports.
    public var methods: [String]
    /// Largest `limit` that `groups.log` accepts.
    public var maxLogLimit: Int

    enum CodingKeys: String, CodingKey {
        case driver, features, methods
        case protocolVersion = "protocol_version"
        case persistentProcess = "persistent_process"
        case authorityGatewayID = "authority_gateway_id"
        case roomLink = "room_link"
        case maxLogLimit = "max_log_limit"
    }
}

/// Params of `groups.create`. Creating an existing room id is idempotent.
public struct GroupsCreateParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Id of the new room, chosen by the client.
    public var roomID: String
    /// Room name.
    public var name: String
    /// Members to add.
    public var members: [RoomMember]
    /// Gateway that should own the room. Defaults to this gateway.
    public var authorityGatewayID: String?

    /// Creates a room.
    public init(
        roomID: String, name: String, members: [RoomMember], profile: String? = nil,
        authorityGatewayID: String? = nil
    ) {
        self.roomID = roomID
        self.name = name
        self.members = members
        self.profile = profile
        self.authorityGatewayID = authorityGatewayID
    }

    enum CodingKeys: String, CodingKey {
        case profile, name, members
        case roomID = "room_id"
        case authorityGatewayID = "authority_gateway_id"
    }
}

/// Result of `groups.create`.
public struct GroupsCreateResult: Sendable, Equatable, Codable {
    /// The room.
    public var room: Room
}

/// Params of `groups.list`.
public struct GroupsListParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Include disbanded rooms.
    public var includeDisbanded: Bool?
    /// Maximum rows.
    public var limit: Int?
    /// Rows to skip.
    public var offset: Int?

    /// Creates list params.
    public init(profile: String? = nil, includeDisbanded: Bool? = nil, limit: Int? = nil, offset: Int? = nil) {
        self.profile = profile
        self.includeDisbanded = includeDisbanded
        self.limit = limit
        self.offset = offset
    }

    enum CodingKeys: String, CodingKey {
        case profile, limit, offset
        case includeDisbanded = "include_disbanded"
    }
}

/// Result of `groups.list`.
public struct GroupsListResult: Sendable, Equatable, Codable {
    /// Rooms.
    public var rooms: [Room]
    /// Offset of the next page. Nil on the last page.
    public var nextOffset: Int?

    enum CodingKeys: String, CodingKey {
        case rooms
        case nextOffset = "next_offset"
    }
}

/// The payload of a room message (`groups.send`).
public struct RoomMessagePayload: Sendable, Equatable, Codable {
    /// Message text. Use @handle to address a member.
    public var text: String
    /// Thread the message belongs to, when any.
    public var threadID: String?

    /// Creates a message payload.
    public init(text: String, threadID: String? = nil) {
        self.text = text
        self.threadID = threadID
    }

    enum CodingKeys: String, CodingKey {
        case text
        case threadID = "thread_id"
    }
}

/// Params of `groups.send`. An `eventID` makes the send idempotent; the same id with a different payload fails (4111).
public struct GroupsSendParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to send to.
    public var roomID: String
    /// Idempotency key for this send.
    public var eventID: String?
    /// The message.
    public var payload: RoomMessagePayload

    /// Creates a send.
    public init(roomID: String, payload: RoomMessagePayload, eventID: String? = nil, profile: String? = nil) {
        self.roomID = roomID
        self.payload = payload
        self.eventID = eventID
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile, payload
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

/// Result of `groups.send`.
public struct GroupsSendResult: Sendable, Equatable, Codable {
    /// The stored event.
    public var event: RoomEvent
    /// Echo of the client's event id.
    public var clientEventID: String?
    /// True when the room accepted the message.
    public var accepted: Bool
    /// True when the room started a turn for it.
    public var driverStarted: Bool

    enum CodingKeys: String, CodingKey {
        case event, accepted
        case clientEventID = "client_event_id"
        case driverStarted = "driver_started"
    }
}

/// Params of `groups.log`.
public struct GroupsLogParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to read.
    public var roomID: String
    /// Return events after this sequence number.
    public var sinceSeq: Int?
    /// Maximum events to return.
    public var limit: Int?
    /// Include a disbanded room's log.
    public var includeDisbanded: Bool?

    /// Creates a log query.
    public init(
        roomID: String, profile: String? = nil, sinceSeq: Int? = nil, limit: Int? = nil,
        includeDisbanded: Bool? = nil
    ) {
        self.roomID = roomID
        self.profile = profile
        self.sinceSeq = sinceSeq
        self.limit = limit
        self.includeDisbanded = includeDisbanded
    }

    enum CodingKeys: String, CodingKey {
        case profile, limit
        case roomID = "room_id"
        case sinceSeq = "since_seq"
        case includeDisbanded = "include_disbanded"
    }
}

/// Result of `groups.log`.
public struct GroupsLogResult: Sendable, Equatable, Codable {
    /// Events, in sequence order.
    public var events: [RoomEvent]
    /// Cursor for the next call (`since_seq`).
    public var cursor: Int
    /// Highest sequence number in the room.
    public var latestSeq: Int
    /// True when more events remain.
    public var hasMore: Bool
    /// The room's authority at read time.
    public var authority: RoomAuthority

    enum CodingKeys: String, CodingKey {
        case events, cursor, authority
        case latestSeq = "latest_seq"
        case hasMore = "has_more"
    }
}

/// Params of `groups.state`.
public struct GroupsStateParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to read.
    public var roomID: String
    /// Include a disbanded room.
    public var includeDisbanded: Bool?

    /// Creates a state query.
    public init(roomID: String, profile: String? = nil, includeDisbanded: Bool? = nil) {
        self.roomID = roomID
        self.profile = profile
        self.includeDisbanded = includeDisbanded
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case roomID = "room_id"
        case includeDisbanded = "include_disbanded"
    }
}

/// Result of `groups.state`.
public struct GroupsStateResult: Sendable, Equatable, Codable {
    /// The room.
    public var room: Room
    /// Driver state, when the room has one.
    public var driverStatus: RoomDriverStatus?

    enum CodingKeys: String, CodingKey {
        case room
        case driverStatus = "driver_status"
    }
}

/// Params of `groups.stop`: stop the room's running turns.
public struct GroupsStopParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to stop.
    public var roomID: String
    /// Cancel only the turn with this id.
    public var cancelID: String?

    /// Creates a stop request.
    public init(roomID: String, profile: String? = nil, cancelID: String? = nil) {
        self.roomID = roomID
        self.profile = profile
        self.cancelID = cancelID
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case roomID = "room_id"
        case cancelID = "cancel_id"
    }
}

/// Result of `groups.stop`.
public struct GroupsStopResult: Sendable, Equatable, Codable {
    /// How many turns were cancelled.
    public var cancelled: Int
}

/// Params of `groups.disband`.
public struct GroupsDisbandParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to disband.
    public var roomID: String
    /// Cancel running turns first, with this id.
    public var cancelID: String?

    /// Creates a disband request.
    public init(roomID: String, profile: String? = nil, cancelID: String? = nil) {
        self.roomID = roomID
        self.profile = profile
        self.cancelID = cancelID
    }

    enum CodingKeys: String, CodingKey {
        case profile
        case roomID = "room_id"
        case cancelID = "cancel_id"
    }
}

/// Result of `groups.disband`.
public struct GroupsDisbandResult: Sendable, Equatable, Codable {
    /// What remains of the room.
    public var tombstone: RoomTombstone
}

/// Params of `groups.rename`.
public struct GroupsRenameParams: Sendable, Equatable, Codable {
    /// Profile the request is scoped to.
    public var profile: String?
    /// Room to rename.
    public var roomID: String
    /// Idempotency key for the rename.
    public var eventID: String
    /// New name.
    public var name: String

    /// Creates a rename request.
    public init(roomID: String, eventID: String, name: String, profile: String? = nil) {
        self.roomID = roomID
        self.eventID = eventID
        self.name = name
        self.profile = profile
    }

    enum CodingKeys: String, CodingKey {
        case profile, name
        case roomID = "room_id"
        case eventID = "event_id"
    }
}

/// Result of `groups.rename`.
public struct GroupsRenameResult: Sendable, Equatable, Codable {
    /// The renamed room.
    public var room: Room
}
