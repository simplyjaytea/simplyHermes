import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomPresentationTests {
    private func status(working: Bool) throws -> RoomDriverStatus {
        try JSONDecoder().decode(
            RoomDriverStatus.self,
            from: Data(
                #"{"running": true, "working": \#(working), "blocked": false, "counts": {}, "pending_actions": [], "peer_routes": []}"#
                    .utf8))
    }

    private func capabilities() throws -> GroupsCapabilitiesResult {
        let json = #"""
            {"protocol_version": 2, "driver": true, "persistent_process": true,
             "authority_gateway_id": "install:I1", "room_link": {"enabled": true},
             "features": [], "methods": [], "max_log_limit": 500}
            """#
        return try JSONDecoder().decode(GroupsCapabilitiesResult.self, from: Data(json.utf8))
    }

    private func room(authority: String = "install:I1", peer: Bool = false) throws -> Room {
        let target = peer ? #"{"kind": "peer", "peer_id": "p1"}"# : #"{"kind": "local", "profile": "ops"}"#
        let json = #"""
            {"room_id": "room-1", "name": "Release room",
             "members": [{"member_id": "default", "profile": "default", "handle": "hermes",
                           "target": {"kind": "local", "profile": "default"}},
                         {"member_id": "ops", "profile": "ops", "handle": "ops", "target": \#(target)}],
             "authority_gateway_id": "\#(authority)", "authority_epoch": 1, "revision": 1,
             "created_at": 1.0, "updated_at": 1.0}
            """#
        return try JSONDecoder().decode(Room.self, from: Data(json.utf8))
    }

    @Test func theTintHashMatchesDesktop() {
        // ((111 * 31) + 112) * 31 + 115 = 110258, and 110258 % 360 = 98.
        #expect(RoomAvatarTint.hue(forProfile: "ops") == 98)
    }

    @Test func theDefaultAndBlankProfilesHaveNoTint() {
        #expect(RoomAvatarTint.hue(forProfile: "default") == nil)
        #expect(RoomAvatarTint.hue(forProfile: "") == nil)
    }

    @Test func aWorkingRoomPollsEverySecondAndAnIdleOneEveryFiveSeconds() throws {
        #expect(RoomStatus.pollInterval(for: try status(working: true)) == 1)
        #expect(RoomStatus.pollInterval(for: try status(working: false)) == 5)
        #expect(RoomStatus.pollInterval(for: nil) == 5)
    }

    @Test func aMemberIsNamedByItsDisplayNameThenItsProfile() {
        #expect(RoomTimeline.label(for: .local(profile: "default")) == "Hermes")
        #expect(RoomTimeline.label(for: .local(profile: "research", displayName: "Research bot")) == "Research bot")
    }

    @Test func aRoomOnTheGatewayThatHoldsItHasNoReadOnlyNote() throws {
        #expect(try room().readOnlyNote(on: capabilities()) == nil)
    }

    @Test func aRoomAnotherGatewayManagesSaysSo() throws {
        let note = try room(authority: "install:I2").readOnlyNote(on: capabilities())

        #expect(note?.hasPrefix("This Group Chat is managed by another gateway") == true)
    }

    @Test func aPeerMemberSendsTheUserToDesktop() throws {
        let note = try room(peer: true).readOnlyNote(on: capabilities())

        #expect(note?.contains("Hermes Desktop") == true)
    }
}
