import Foundation
import Testing

@testable import HermesKit

@Suite struct RoomMentionTests {
    private let handles = ["ops", "research"]

    @Test func onlyRoutedMentionsAreStyled() {
        let text = "@ops and @research, @user, @all, @nobody, mail a@b.com"

        let kinds = RoomMentions.spans(in: text, handles: handles).map(\.kind)

        #expect(kinds == [.member("ops"), .member("research"), .human, .everyone])
    }

    @Test func aTokenWithAColonIsNotAHandle() {
        #expect(RoomMentions.spans(in: "@ops: do x", handles: handles).isEmpty)
    }

    @Test func theSpanCoversTheAtSignThroughTheToken() throws {
        let text = "hi @ops!"

        let span = try #require(RoomMentions.spans(in: text, handles: handles).first)

        #expect(String(text[span.range]) == "@ops")
    }

    @Test func thePickerCompletesTheWordUnderTheCaret() throws {
        let text = "hi @o"

        let completion = try #require(RoomMentions.completion(in: text, caret: text.endIndex))

        #expect(completion.query == "o")
        #expect(RoomMentions.options(for: completion, handles: handles) == ["ops"])
        let inserted = RoomMentions.inserting("ops", into: text, replacing: completion)
        #expect(inserted == "hi @ops ")
    }

    @Test func thePickerOffersTheBroadcastsFirst() throws {
        let text = "@"

        let completion = try #require(RoomMentions.completion(in: text, caret: text.endIndex))

        #expect(RoomMentions.options(for: completion, handles: handles) == ["everyone", "all", "ops", "research"])
    }

    @Test func aMentionInsideAWordDoesNotOpenThePicker() {
        let text = "mail a@o"

        #expect(RoomMentions.completion(in: text, caret: text.endIndex) == nil)
    }

    @Test func slashCommandsAreRefused() {
        #expect(RoomMentions.isSlashCommand("/new"))
        #expect(RoomMentions.isSlashCommand("/new chat"))
        #expect(!RoomMentions.isSlashCommand("/New"))
        #expect(!RoomMentions.isSlashCommand("/"))
        #expect(!RoomMentions.isSlashCommand("/tmp/file"))
        #expect(!RoomMentions.isSlashCommand(" /new"))
    }

    @Test func userMentionsBadgeTheRoomAsAWord() {
        #expect(RoomMentions.asksUser("@user please check"))
        #expect(RoomMentions.asksUser("@User."))
        #expect(!RoomMentions.asksUser("@users are here"))
        #expect(!RoomMentions.asksUser("@user_x"))
    }
}
