import Foundation
import Testing

@testable import HermesKit

@Suite struct BotEditTests {
    @Test func seedsFromTheRosterEntry() throws {
        let row = BotRosterRow(
            profile: "ops", description: "Runs the nightly jobs",
            meta: BotMetaObject(try botJSON(#"{"title": "Ops", "pinned": true, "hidden": true}"#)))
        let entry = try #require(BotRoster.entries([Self.source(row)]).first)

        let edit = BotEdit(entry: entry)

        #expect(edit.title == entry.title)
        #expect(edit.role == "Runs the nightly jobs")
        #expect(edit.isPinned)
        #expect(edit.isHidden)
        #expect(edit.avatar == nil)
    }

    @Test func aBotWithoutARoleSeedsAnEmptyRole() throws {
        let entry = try #require(BotRoster.entries([Self.source(BotRosterRow(profile: "ops"))]).first)

        #expect(BotEdit(entry: entry).role == "")
    }

    private static func source(_ row: BotRosterRow) -> BotRosterSource {
        BotRosterSource(
            connectionID: UUID(), label: "This iPhone", isPrimary: true, installID: "I1", isRich: true, rows: [row])
    }
}
