import Foundation
import Testing

@testable import HermesKit

@Suite struct BotRosterTests {
    private static let phone = UUID()
    private static let office = UUID()

    private func source(
        _ id: UUID, label: String, primary: Bool = false, priority: Int = 0, install: String? = nil,
        reachable: Bool = true, rich: Bool = true, rows: [BotRosterRow]
    ) -> BotRosterSource {
        BotRosterSource(
            connectionID: id, label: label, isPrimary: primary, priority: priority, installID: install,
            reachable: reachable, isRich: rich, rows: rows)
    }

    @Test func sameInstallAndProfileShowsOnceFromThePrimaryGateway() {
        let sources = [
            source(
                Self.phone, label: "This iPhone", primary: true, install: "I1",
                rows: [BotRosterRow(profile: "ops", backendTitle: "Local Ops")]),
            source(
                Self.office, label: "Office", priority: 2, install: "I1", rich: false,
                rows: [BotRosterRow(profile: "ops", backendTitle: "Remote Ops"), BotRosterRow(profile: "research")]),
        ]
        let entries = BotRoster.entries(sources)
        #expect(entries.map(\.profile).sorted() == ["ops", "research"])
        let ops = entries.first { $0.profile == "ops" }
        #expect(ops?.title == "Local Ops")
        #expect(ops?.connectionID == Self.phone)
        #expect(ops?.handle == "ops")
        #expect(entries.first { $0.profile == "research" }?.status == .onDemand)
    }

    @Test func sameProfileOnTwoInstallsGetLabelledHandles() {
        let sources = [
            source(
                Self.phone, label: "This iPhone", primary: true, install: "I1", rows: [BotRosterRow(profile: "ops")]),
            source(
                Self.office, label: "Office Linux", install: "I2", rich: false, rows: [BotRosterRow(profile: "ops")]),
        ]
        let handles = BotRoster.entries(sources).map(\.handle).sorted()
        #expect(handles == ["ops-office-linux", "ops-this-iphone"])
    }

    @Test func rowsWithoutAnInstallIDAreNeverMerged() {
        let sources = [
            source(Self.phone, label: "A", primary: true, rows: [BotRosterRow(profile: "ops")]),
            source(Self.office, label: "B", rows: [BotRosterRow(profile: "ops")]),
        ]
        #expect(BotRoster.entries(sources).count == 2)
    }

    @Test func pinnedBotsLeadThenNewestActivity() throws {
        let rows = [
            BotRosterRow(profile: "old", meta: BotMetaObject(try botJSON(#"{"pinned": true}"#)), lastActive: 100),
            BotRosterRow(profile: "newest", lastActive: 300),
            BotRosterRow(profile: "middle", lastActive: 200),
        ]
        let entries = BotRoster.entries([source(Self.phone, label: "Phone", install: "I1", rows: rows)])
        #expect(entries.map(\.profile) == ["old", "newest", "middle"])
    }

    @Test func defaultProfileShowsAsHermes() {
        let rows = [BotRosterRow(profile: "default", isDefault: true)]
        let entry = BotRoster.entries([source(Self.phone, label: "Phone", install: "I1", rows: rows)]).first
        #expect(entry?.title == "Hermes")
        #expect(entry?.mention == "@hermes")
    }

    @Test func unreachableGatewayKeepsItsRowsAsRetained() {
        let rows = [BotRosterRow(profile: "ops")]
        let entry = BotRoster.entries([
            source(Self.office, label: "Office", install: "I2", reachable: false, rows: rows)
        ]).first
        #expect(entry?.status == .unavailable)
        #expect(entry?.isRetained == true)
    }

    @Test func sectionsSplitByGatewayAndPutHiddenBotsLast() throws {
        let sources = [
            source(
                Self.phone, label: "This iPhone", primary: true, install: "I1",
                rows: [
                    BotRosterRow(profile: "ops"),
                    BotRosterRow(profile: "archive", meta: BotMetaObject(try botJSON(#"{"hidden": true}"#))),
                ]),
            source(Self.office, label: "Office Linux", install: "I2", rows: [BotRosterRow(profile: "research")]),
        ]
        let sections = BotRoster.sections(BotRoster.entries(sources), sources: sources)
        #expect(sections.map(\.title) == ["Office Linux", "This iPhone", "Hidden"])
        #expect(sections.last?.entries.map(\.profile) == ["archive"])
    }

    @Test func oneGatewayIsOneUntitledSection() {
        let sources = [source(Self.phone, label: "This iPhone", install: "I1", rows: [BotRosterRow(profile: "ops")])]
        let sections = BotRoster.sections(BotRoster.entries(sources), sources: sources)
        #expect(sections.map(\.title) == [""])
        #expect(sections.first?.entries.count == 1)
    }

    @Test func searchMatchesNameRoleAndPreviewAndIncludesHiddenBots() throws {
        let rows = [
            BotRosterRow(profile: "ops", description: "Runs deploys"),
            BotRosterRow(profile: "research", preview: "Found the paper"),
            BotRosterRow(
                profile: "archive", meta: BotMetaObject(try botJSON(#"{"hidden": true, "title": "Old Notes"}"#))),
        ]
        let sources = [source(Self.phone, label: "Phone", install: "I1", rows: rows)]
        let entries = BotRoster.entries(sources)
        func found(_ query: String) -> [String] {
            BotRoster.sections(entries, sources: sources, query: query).flatMap(\.entries).map(\.profile)
        }
        #expect(found("@DEPLOYS") == ["ops"])
        #expect(found("paper") == ["research"])
        #expect(found("old notes") == ["archive"])
        #expect(Set(found("   ")) == ["ops", "research", "archive"])
    }

    @Test func activityPrefersWorkingThenActive() {
        let now = 10_000.0
        #expect(BotRoster.activity(lastActive: nil, workerActiveAt: now - 10, runningTurn: false, now: now) == .working)
        #expect(
            BotRoster.activity(lastActive: now - 30, workerActiveAt: now - 200, runningTurn: false, now: now) == .active
        )
        #expect(BotRoster.activity(lastActive: now - 200, workerActiveAt: nil, runningTurn: true, now: now) == .active)
        #expect(BotRoster.activity(lastActive: now - 200, workerActiveAt: nil, runningTurn: false, now: now) == .idle)
        #expect(BotRoster.activity(lastActive: nil, workerActiveAt: nil, runningTurn: false, now: now) == .idle)
    }

    @Test func recentMeansSevenDays() {
        let now = 1_000_000.0
        #expect(BotRoster.isRecent(lastActive: now - 6 * 86_400, now: now))
        #expect(!BotRoster.isRecent(lastActive: now - 8 * 86_400, now: now))
        #expect(!BotRoster.isRecent(lastActive: nil, now: now))
    }
}
