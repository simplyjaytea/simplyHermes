import Foundation
import Testing

@testable import HermesKit

/// Answers each method from a script of replies. A method's last reply repeats once its script runs out.
private actor FakeRoomGateway: RoomGateway {
    enum Reply: Sendable {
        case json(String)
        case failure(RPCError)
    }

    struct Call: Sendable {
        let method: String
        let params: JSONValue?
    }

    private var scripts: [String: [Reply]]
    private(set) var calls: [Call] = []

    init(_ scripts: [String: [Reply]]) {
        self.scripts = scripts
    }

    func call<Value: Decodable & Sendable>(
        _ method: String, params: (any Encodable & Sendable)?, as type: Value.Type, timeout: Double?
    ) async throws -> Value {
        calls.append(Call(method: method, params: try params.map { try JSONValue(encoding: $0) }))
        guard let script = scripts[method], let reply = script.first else {
            throw RPCError(code: -32601, message: "no reply scripted for \(method)")
        }
        if script.count > 1 { scripts[method] = Array(script.dropFirst()) }
        switch reply {
        case .json(let text): return try JSONDecoder().decode(Value.self, from: Data(text.utf8))
        case .failure(let error): throw error
        }
    }
}

/// Shapes recorded from `Fixtures/bot_and_group_room.jsonl`: a room of two local bots, `default` and `ops`.
private let capabilitiesJSON = #"""
    {"protocol_version": 2, "driver": true, "persistent_process": true, "authority_gateway_id": "install:I1",
     "room_link": {"enabled": true}, "features": [], "methods": ["groups.capabilities", "groups.create"],
     "max_log_limit": 500}
    """#

private let roomJSON = #"""
    {"room_id": "room-1", "name": "Release room",
     "members": [{"member_id": "default", "profile": "default", "handle": "hermes",
                   "target": {"kind": "local", "profile": "default"}},
                 {"member_id": "ops", "profile": "ops", "handle": "ops", "target": {"kind": "local", "profile": "ops"}}],
     "authority_gateway_id": "install:I1", "authority_epoch": 1, "revision": 1, "created_at": 1791948523.75,
     "updated_at": 1791948523.75, "idempotent": false, "latest_seq": 4}
    """#

private let userEvent = #"""
    {"room_id": "room-1", "seq": 1, "event_id": "user:abc", "kind": "message.user",
     "actor": {"id": "desktop", "kind": "user"}, "authority_epoch": 1,
     "payload": {"text": "@ops hello", "thread_id": "thread-1"}, "created_at": 1791948523.77, "idempotent": false}
    """#

private let memberEvent = #"""
    {"room_id": "room-1", "seq": 2, "event_id": "dmessage:1", "kind": "message.member",
     "actor": {"id": "ops", "kind": "member", "profile": "ops"}, "authority_epoch": 1,
     "payload": {"discussion_event_id": "user:abc", "member_id": "ops", "member_index": 0, "round_index": 0,
                 "task_id": "dtask:1", "text": "Hello from the fake LLM.", "thread_id": "thread-1", "turn_id": "t1"},
     "created_at": 1791948524.0, "idempotent": false}
    """#

private let settledEvent = #"""
    {"room_id": "room-1", "seq": 3, "event_id": "turn-settled:1", "kind": "turn.settled",
     "actor": {"id": "install:I1", "kind": "gateway"}, "authority_epoch": 1,
     "payload": {"member_id": "ops", "member_index": 0, "message_event_id": "dmessage:1", "passed": false,
                 "round_index": 0, "seen_through_seq": 1, "task_id": "dtask:1", "thread_id": "thread-1", "turn_id": "t1"},
     "created_at": 1791948524.1, "idempotent": false}
    """#

private let activityEvent = #"""
    {"room_id": "room-1", "seq": 4, "event_id": "room-activity:1", "kind": "room.activity",
     "actor": {"id": "install:I1", "kind": "gateway"}, "authority_epoch": 1,
     "payload": {"discussion_event_id": "user:abc", "reason_code": "silent_round", "status": "settled",
                 "thread_id": "thread-1"},
     "created_at": 1791948524.2, "idempotent": false}
    """#

private let firstLogPage = #"""
    {"events": [\#(userEvent)], "cursor": 1, "latest_seq": 4, "has_more": true,
     "authority": {"gateway_id": "install:I1", "epoch": 1}}
    """#

private let secondLogPage = #"""
    {"events": [\#(memberEvent), \#(settledEvent), \#(activityEvent)], "cursor": 4, "latest_seq": 4, "has_more": false,
     "authority": {"gateway_id": "install:I1", "epoch": 1}}
    """#

private func state(working: Bool) -> String {
    #"""
    {"room": \#(roomJSON), "driver_status": {"running": true, "working": \#(working), "blocked": false,
      "counts": {"running": 1}, "pending_actions": [], "peer_routes": []}}
    """#
}

private let approvalStatus = #"""
    {"room": \#(roomJSON), "driver_status": {"running": true, "working": true, "blocked": false, "counts": {},
      "pending_actions": [{"kind": "approval", "task_id": "dtask:1", "member_id": "ops", "execution_generation": 2,
        "run_id": "run-1", "session_id": "s-1", "request_id": "req-1",
        "approval": {"choices": ["once", "deny"], "command": "rm -rf build"}}], "peer_routes": []}}
    """#

/// Decodes a fixture string as the type the client returns.
private func decode<Value: Decodable>(_ type: Value.Type, _ text: String) throws -> Value {
    try JSONDecoder().decode(type, from: Data(text.utf8))
}

/// The refusal a call throws before it reaches the gateway, or nil when it went through.
private func refusal(_ body: () async throws -> Void) async -> RoomError? {
    do {
        try await body()
        return nil
    } catch {
        return error as? RoomError
    }
}

@Suite struct RoomClientTests {
    @Test func createSendsTheDocumentedKeysAndNoTargets() async throws {
        let fake = FakeRoomGateway(["groups.create": [.json(#"{"room": \#(roomJSON)}"#)]])
        let client = RoomClient(gateway: fake)
        let draft = RoomDraft(name: "Release room", members: [.local(profile: "default"), .local(profile: "ops")])

        let room = try await client.create(draft, roomID: "room-1")

        #expect(room.members.map(\.handle) == ["hermes", "ops"])
        let params = try #require(await fake.calls.first?.params)
        let members = try #require(params["members"]?.arrayValue)
        #expect(members.allSatisfy { $0["target"] == nil })
        #expect(members.first?["handle"]?.stringValue == "hermes")
        #expect(params["authority_gateway_id"] == nil)
    }

    @Test func logReadsEveryPageAndTurnsItIntoRows() async throws {
        let fake = FakeRoomGateway(["groups.log": [.json(firstLogPage), .json(secondLogPage)]])
        let client = RoomClient(gateway: fake)

        let log = try await client.log(roomID: "room-1")

        #expect(log.events.map(\.seq) == [1, 2, 3, 4])
        #expect(log.latestSeq == 4)
        #expect(await fake.calls.map { $0.params?["since_seq"]?.intValue } == [0, 1])
        let rows = RoomTimeline.rows(from: log.events, labels: ["ops": "Ops"])
        #expect(rows.map(\.id) == [1, 2, 4])
        guard case .member(_, let memberID, let text, _, _) = rows[1] else {
            Issue.record("row 2 should be the member's reply")
            return
        }
        #expect(memberID == "ops")
        #expect(text == "Hello from the fake LLM.")
    }

    @Test func stopAndStatusFollowTheDriverState() async throws {
        let fake = FakeRoomGateway([
            "groups.state": [.json(state(working: true)), .json(state(working: false))],
            "groups.stop": [.json(#"{"cancelled": 1}"#)],
        ])
        let client = RoomClient(gateway: fake)

        let busy = try await client.state(roomID: "room-1")
        #expect(RoomStatus.showsStop(busy.driverStatus))
        #expect(RoomStatus.line(for: busy.driverStatus) == "The room is working…")

        #expect(try await client.stop(roomID: "room-1", cancelID: "stop-1") == 1)
        #expect(await fake.calls.last?.params?["cancel_id"]?.stringValue == "stop-1")

        let idle = try await client.state(roomID: "room-1")
        #expect(!RoomStatus.showsStop(idle.driverStatus))
        #expect(RoomStatus.line(for: idle.driverStatus) == nil)
    }

    @Test func aRefusedSendSaysWhatWentWrong() async throws {
        let refused = RPCError(code: 4123, message: "Group Chat worker is unavailable.")
        let fake = FakeRoomGateway(["groups.send": [.failure(refused)]])
        let client = RoomClient(gateway: fake)

        do {
            _ = try await client.send(
                roomID: "room-1", eventID: RoomIdentifier.newEventID(), text: "hi", threadID: "thread-1")
            Issue.record("the send should have failed")
        } catch {
            #expect(
                RoomFailure.message(for: error)
                    == "The Group Chat worker is not running. Restart the Hermes gateway and try again.")
        }
    }

    @Test func badInputIsRefusedBeforeAnySend() async throws {
        let fake = FakeRoomGateway([:])
        let client = RoomClient(gateway: fake)
        let eventID = RoomIdentifier.newEventID()

        #expect(
            await refusal { _ = try await client.send(roomID: "room-1", eventID: eventID, text: "  ", threadID: "t1") }
                == .emptyMessage)
        #expect(
            await refusal {
                _ = try await client.send(roomID: "room-1", eventID: eventID, text: "/new", threadID: "t1")
            }
                == .slashCommand)
        #expect(
            await refusal { _ = try await client.send(roomID: "bad id", eventID: eventID, text: "hi", threadID: "t1") }
                == .invalidIdentifier("bad id"))
        #expect(await fake.calls.isEmpty)
    }

    @Test func approvalAnswersTheActionTheStatusNamed() async throws {
        let fake = FakeRoomGateway(["groups.approve": [.json("{}")]])
        let client = RoomClient(gateway: fake)
        let status = try decode(GroupsStateResult.self, approvalStatus).driverStatus
        let action = try #require(RoomStatus.pendingApproval(in: status))
        #expect(RoomStatus.line(for: status) == "Waiting for your answer…")

        try await client.approve(roomID: "room-1", action: action, choice: .once)

        let params = try #require(await fake.calls.last?.params)
        #expect(params["member_id"]?.stringValue == "ops")
        #expect(params["task_id"]?.stringValue == "dtask:1")
        #expect(params["execution_generation"]?.intValue == 2)
        #expect(params["request_id"]?.stringValue == "req-1")
        #expect(params["choice"]?.stringValue == "once")
        #expect(params["profile"] == nil)
    }

    @Test func roomsFollowTheNextOffsetUntilItRunsOut() async throws {
        let fake = FakeRoomGateway([
            "groups.list": [
                .json(#"{"rooms": [\#(roomJSON)], "next_offset": 500}"#),
                .json(#"{"rooms": [], "next_offset": null}"#),
            ]
        ])
        let client = RoomClient(gateway: fake)

        let rooms = try await client.rooms()

        #expect(rooms.count == 1)
        #expect(await fake.calls.map { $0.params?["offset"]?.intValue } == [0, 500])
    }

    @Test func aRoomHomedElsewhereOrWithAPeerMemberIsReadOnly() throws {
        let capabilities = try decode(GroupsCapabilitiesResult.self, capabilitiesJSON)
        let room = try decode(Room.self, roomJSON)
        #expect(!room.isReadOnly(on: capabilities))

        var elsewhere = room
        elsewhere.authorityGatewayID = "install:I2"
        #expect(elsewhere.isReadOnly(on: capabilities))

        var withPeer = room
        withPeer.members[1].target = try decode(JSONValue.self, #"{"kind": "peer", "peer_id": "p1"}"#)
        #expect(withPeer.isReadOnly(on: capabilities))
    }

    @Test func disbandReturnsTheTombstone() async throws {
        let fake = FakeRoomGateway([
            "groups.disband": [
                .json(#"{"tombstone": {"room_id": "room-1", "disbanded_at": 1791948525.9, "idempotent": false}}"#)
            ]
        ])
        let client = RoomClient(gateway: fake)

        let tombstone = try await client.disband(roomID: "room-1")

        #expect(tombstone.roomID == "room-1")
        #expect(tombstone.idempotent == false)
    }

    @Test func retryAsksTheRoomToRunTheTaskAgain() async throws {
        let fake = FakeRoomGateway(["groups.retry": [.json(#"{"retried": true}"#)]])
        let client = RoomClient(gateway: fake)

        #expect(try await client.retry(roomID: "room-1", taskID: "dtask:1"))

        let params = try #require(await fake.calls.last?.params)
        #expect(params["task_id"]?.stringValue == "dtask:1")
    }
}
