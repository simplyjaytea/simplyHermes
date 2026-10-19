import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomTranscriptTests {
    private func event(_ seq: Int) throws -> RoomEvent {
        let json = #"""
            {"room_id": "room-1", "seq": \#(seq), "event_id": "e\#(seq)", "kind": "message.user",
             "actor": {"id": "desktop", "kind": "user"}, "payload": {"text": "m\#(seq)", "thread_id": "t1"},
             "created_at": 1.0}
            """#
        return try JSONDecoder().decode(RoomEvent.self, from: Data(json.utf8))
    }

    private func log(_ seqs: [Int], cursor: Int) throws -> RoomLog {
        RoomLog(
            events: try seqs.map { try event($0) }, cursor: cursor, latestSeq: 4,
            authority: RoomAuthority(gatewayID: "install:I1", epoch: 1))
    }

    @Test func mergeKeepsOneEventPerSequenceNumberInOrder() throws {
        var transcript = RoomTranscript()

        transcript.merge(try log([2, 1], cursor: 2))
        transcript.merge(try log([2, 3], cursor: 3))

        #expect(transcript.events.map(\.seq) == [1, 2, 3])
        #expect(transcript.cursor == 3)
    }

    @Test func aRepeatedReadChangesNothing() throws {
        var transcript = RoomTranscript()
        transcript.merge(try log([1], cursor: 1))
        let before = transcript

        transcript.merge(try log([], cursor: 1))

        #expect(transcript == before)
    }

    @Test func resetStartsFromTheTop() throws {
        var transcript = RoomTranscript()
        transcript.merge(try log([1, 2], cursor: 2))

        transcript.reset()

        #expect(transcript.events.isEmpty)
        #expect(transcript.cursor == 0)
    }

    @Test func rowsFollowTheEventsHeld() throws {
        var transcript = RoomTranscript()
        transcript.merge(try log([1, 2], cursor: 2))

        #expect(transcript.rows(labels: [:]).map(\.id) == [1, 2])
    }
}

@Suite struct RoomOutgoingMessageTests {
    @Test func aBlankMessageIsRefused() {
        #expect(RoomOutgoingMessage(text: "   \n") == nil)
    }

    @Test func theTextIsTrimmedAndTheIdsAreValid() throws {
        let message = try #require(RoomOutgoingMessage(text: "  hi there \n"))

        #expect(message.text == "hi there")
        #expect(RoomIdentifier.isValid(message.eventID))
        #expect(message.threadID.hasPrefix("t"))
        #expect(RoomIdentifier.isValid(message.threadID))
    }
}
