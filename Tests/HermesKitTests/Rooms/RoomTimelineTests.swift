import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomTimelineTests {
    private func event(_ seq: Int, kind: String, payload: String) throws -> RoomEvent {
        let json = #"""
            {"room_id": "room-1", "seq": \#(seq), "event_id": "e\#(seq)", "kind": "\#(kind)",
             "actor": {"id": "ops", "kind": "member"}, "payload": \#(payload), "created_at": 1.0}
            """#
        return try JSONDecoder().decode(RoomEvent.self, from: Data(json.utf8))
    }

    @Test func unknownKindsProduceNoRow() throws {
        let events = [try event(1, kind: "bot.wat", payload: "{}")]

        #expect(RoomTimeline.rows(from: events).isEmpty)
    }

    @Test func aFailedTurnNamesTheMemberAndItsFirstErrorLine() throws {
        let events = [
            try event(
                1, kind: "turn.failed",
                payload: #"{"member_id": "ops", "error": "boom\nstack trace", "reason_code": "x"}"#)
        ]

        let rows = RoomTimeline.rows(from: events, labels: ["ops": "Ops bot"])

        guard case .activity(_, let text) = rows.first else {
            Issue.record("a failed turn should be an activity row")
            return
        }
        #expect(text == "Ops bot hit an error: boom")
    }

    @Test func aPassedTurnIsShownAndAnUnpassedOneIsNot() throws {
        let events = [
            try event(1, kind: "turn.settled", payload: #"{"member_id": "ops", "passed": true}"#),
            try event(2, kind: "turn.settled", payload: #"{"member_id": "ops", "passed": false}"#),
        ]

        let rows = RoomTimeline.rows(from: events)

        #expect(rows.map(\.id) == [1])
    }

    @Test func theDefaultMemberIsLabelledHermes() throws {
        let events = [try event(1, kind: "turn.settled", payload: #"{"member_id": "default", "passed": true}"#)]

        let rows = RoomTimeline.rows(from: events)

        guard case .activity(_, let text) = rows.first else {
            Issue.record("a passed turn should be an activity row")
            return
        }
        #expect(text == "Hermes passed")
    }

    @Test func aPendingApprovalAnswersTheBanner() throws {
        let status = try JSONDecoder().decode(
            RoomDriverStatus.self,
            from: Data(
                #"""
                {"running": true, "working": true, "blocked": false, "counts": {},
                 "pending_actions": [{"kind": "retry", "task_id": "t9"},
                   {"kind": "approval", "task_id": "t1", "member_id": "ops", "execution_generation": 1,
                    "request_id": "r1", "approval": {"choices": ["once", "deny"]}}],
                 "peer_routes": []}
                """#.utf8))

        #expect(RoomStatus.pendingActions(in: status).count == 2)
        #expect(RoomStatus.pendingApproval(in: status)?.taskID == "t1")
        #expect(RoomStatus.line(for: status) == "Waiting for your answer…")
    }

    @Test func aBlockedRoomShowsStopAndAsksForAttention() throws {
        let status = try JSONDecoder().decode(
            RoomDriverStatus.self,
            from: Data(
                #"{"running": true, "working": false, "blocked": true, "counts": {}, "pending_actions": [], "peer_routes": []}"#
                    .utf8))

        #expect(RoomStatus.showsStop(status))
        #expect(RoomStatus.line(for: status) == "The room needs attention")
    }
}
