import Testing

@testable import HermesKit

@Suite struct BotMetaTests {
    @Test func writeKeepsKeysThisClientDoesNotModel() throws {
        var object = BotMetaObject(try botJSON(#"{"title": "Old", "future": 7}"#))
        object.title = "New"
        #expect(object.writable["title"]?.stringValue == "New")
        #expect(object.writable["future"]?.intValue == 7)
    }

    @Test func writableDropsDesktopChatKey() throws {
        let object = BotMetaObject(try botJSON(#"{"chat": {"id": "x"}, "pinned": true}"#))
        #expect(object.writable["chat"] == nil)
        #expect(object.pinned)
    }

    @Test func blankTitleRemovesTheKey() throws {
        var object = BotMetaObject(try botJSON(#"{"title": "Old"}"#))
        object.title = "  "
        #expect(object.values["title"] == nil)
        #expect(object.title == nil)
    }

    @Test func groupsReadTheSingleGroupAndWriteUniqueNames() throws {
        var object = BotMetaObject(try botJSON(#"{"group": "a"}"#))
        #expect(object.groups == ["a"])
        object.groups = ["b", "b", " ", "c"]
        let expected = try botJSON(#"["b", "c"]"#)
        #expect(object.values["groups"] == expected)
        #expect(object.values["group"]?.stringValue == "b")
        object.groups = []
        #expect(object.values["groups"] == nil)
        #expect(object.values["group"] == nil)
    }

    @Test func payloadCarriesRevisionsOnlyWhereKnown() {
        let (uiMeta, expected) = BotMetaWrite.payload([
            BotMetaWrite(namespace: "hermes-bots", value: .object([:]), expectedRevision: 3),
            BotMetaWrite(namespace: "simplyhermes", value: .object([:]), expectedRevision: nil),
        ])
        #expect(expected == ["hermes-bots": 3])
        #expect(uiMeta["simplyhermes"] == JSONValue.object([:]))
    }

    @Test func payloadWithoutAnyRevisionSendsNoCompareAndSwap() {
        let (_, expected) = BotMetaWrite.payload([
            BotMetaWrite(namespace: "hermes-bots", value: .object([:]), expectedRevision: nil)
        ])
        #expect(expected == nil)
    }

    @Test func lookSetsAvatarAndKeepsOtherKeys() throws {
        let object = BotMetaObject(try botJSON(#"{"other": true}"#))
        let applied = BotAppLook(avatar: .symbol("bolt")).applied(to: object)
        #expect(applied.values["other"]?.boolValue == true)
        #expect(applied.values["version"]?.intValue == 1)
        #expect(BotAppLook(object: applied).avatar == .symbol("bolt"))
        #expect(BotAppLook(object: object).avatar == nil)
    }

    @Test func avatarRoundTripsAndRejectsBadJSON() throws {
        let emoji = BotAvatar.emoji("🦉")
        #expect(BotAvatar(json: emoji.json) == emoji)
        #expect(BotAvatar(json: try botJSON(#"{"kind": "symbol", "value": ""}"#)) == nil)
        #expect(BotAvatar(json: try botJSON(#"{"kind": "photo", "value": "x"}"#)) == nil)
    }

    @Test func monogramFromTheShownName() {
        #expect(BotMonogram.text(for: "Ops Bot") == "OB")
        #expect(BotMonogram.text(for: "research") == "RE")
        #expect(BotMonogram.text(for: "Ana-Maria Lopez") == "AM")
        #expect(BotMonogram.text(for: "🦉") == "?")
    }

    @Test func tintIsStableAndInThePalette() {
        let index = BotTint.index(for: "ops")
        #expect(index == BotTint.index(for: "ops"))
        #expect(BotTint.palette.indices.contains(index))
        // FNV-1a of the empty string is 0x811C9DC5, and that modulo 8 is 5.
        #expect(BotTint.index(for: "") == 5)
    }
}
