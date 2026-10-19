import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomIdentifierTests {
    @Test func validityFollowsTheServerPattern() {
        #expect(RoomIdentifier.isValid("room-1"))
        #expect(RoomIdentifier.isValid("a.b_c:d-e"))
        #expect(!RoomIdentifier.isValid(""))
        #expect(!RoomIdentifier.isValid("-leading"))
        #expect(!RoomIdentifier.isValid("has space"))
        #expect(!RoomIdentifier.isValid(" padded "))
        #expect(RoomIdentifier.isValid(String(repeating: "a", count: RoomIdentifier.maxLength)))
        #expect(!RoomIdentifier.isValid(String(repeating: "a", count: RoomIdentifier.maxLength + 1)))
    }

    @Test func roomIDsCarryTheMillisecondsInBase36() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let prefix = "r" + String(Int64(1_700_000_000_000), radix: 36) + "-"

        let id = RoomIdentifier.newRoomID(now: now)

        #expect(id.hasPrefix(prefix))
        #expect(id.dropFirst(prefix.count).count == 5)
        #expect(RoomIdentifier.isValid(id))
    }

    @Test func threadIDsUseTheThreadPrefix() {
        let id = RoomIdentifier.newThreadID()

        #expect(id.hasPrefix("t"))
        #expect(RoomIdentifier.isValid(id))
    }

    @Test func eventAndCancelIDsAreFreshAndValid() {
        #expect(RoomIdentifier.newEventID() != RoomIdentifier.newEventID())
        #expect(RoomIdentifier.isValid(RoomIdentifier.newEventID()))
        #expect(RoomIdentifier.newCancelID().hasPrefix("stop-"))
        #expect(RoomIdentifier.isValid(RoomIdentifier.newCancelID()))
    }
}
