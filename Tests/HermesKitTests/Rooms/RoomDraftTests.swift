import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomDraftTests {
    @Test func twoBotsMakeAValidDraft() {
        let draft = RoomDraft(name: "  Release room ", members: [.local(profile: "default"), .local(profile: "ops")])

        #expect(draft.problems().isEmpty)
        #expect(draft.effectiveName == "Release room")
    }

    @Test func aBlankNameIsTheMembersNamesJoined() {
        let members = [
            RoomMember.local(profile: "default"),
            RoomMember.local(profile: "research", displayName: "Research bot"),
        ]

        #expect(RoomDraft(name: "   ", members: members).effectiveName == "Hermes, Research bot")
    }

    @Test func theDefaultProfileIsHandledAsHermes() {
        let member = RoomMember.local(profile: "default")

        #expect(member.memberID == "default")
        #expect(member.handle == "hermes")
    }

    @Test func aRoomNeedsTwoToSixMembers() {
        #expect(RoomDraft(name: "Solo", members: [.local(profile: "ops")]).problems() == [.memberCount])

        let seven = (1...7).map { RoomMember.local(profile: "bot\($0)") }
        #expect(RoomDraft(name: "Too many", members: seven).problems() == [.memberCount])
    }

    @Test func handlesAreUniqueWhateverTheCase() {
        let draft = RoomDraft(name: "Dup", members: [.local(profile: "ops"), .local(profile: "Ops")])

        #expect(draft.problems() == [.duplicateHandle("Ops")])
    }

    @Test func reservedHandlesAreRefused() {
        let draft = RoomDraft(name: "Reserved", members: [.local(profile: "ops"), .local(profile: "everyone")])

        #expect(draft.problems() == [.reservedHandle("everyone")])
    }

    @Test func aNameLongerThanTheServerAllowsIsRefused() {
        let long = String(repeating: "n", count: RoomDraft.maxNameLength + 1)
        let draft = RoomDraft(name: long, members: [.local(profile: "ops"), .local(profile: "research")])

        #expect(draft.problems() == [.nameLength])
    }
}
