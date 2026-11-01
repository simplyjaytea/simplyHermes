import Foundation
import Testing

@testable import HermesKit

@Suite struct BotRosterGroupCandidateTests {
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

    @Test func candidatesComeOnlyFromReadyBotsOnTheActiveGateway() {
        let entries = BotRoster.entries([
            source(
                Self.phone, label: "Phone", primary: true, install: "I1",
                rows: [BotRosterRow(profile: "ops"), BotRosterRow(profile: "research")]),
            source(Self.office, label: "Office", install: "I2", rows: [BotRosterRow(profile: "office-bot")]),
            source(Self.phone, label: "Stale", install: "I3", reachable: false, rows: [BotRosterRow(profile: "stale")]),
        ])
        let candidates = BotRoster.groupCandidates(entries, connectionID: Self.phone)
        #expect(candidates.map(\.handle) == ["ops", "research"])
        #expect(candidates.allSatisfy { $0.profile != "office-bot" })
        #expect(candidates.allSatisfy { $0.profile != "stale" })
    }

    @Test func candidateUsesTheRosterTitleAndTheDefaultHandle() {
        let entries = BotRoster.entries([
            source(
                Self.phone, label: "Phone", primary: true, install: "I1",
                rows: [BotRosterRow(profile: "default", isDefault: true, backendTitle: "Hermes")])
        ])
        let candidate = BotRoster.groupCandidates(entries, connectionID: Self.phone).first
        #expect(candidate?.profile == "default")
        #expect(candidate?.handle == "hermes")
        #expect(candidate?.displayName == "Hermes")
    }

    @Test func anotherGatewayGetsNoCandidates() {
        let entries = BotRoster.entries([
            source(Self.phone, label: "Phone", primary: true, install: "I1", rows: [BotRosterRow(profile: "ops")])
        ])
        #expect(BotRoster.groupCandidates(entries, connectionID: Self.office).isEmpty)
    }
}
