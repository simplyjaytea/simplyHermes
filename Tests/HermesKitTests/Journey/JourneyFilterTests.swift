import Foundation
import HermesKit
import Testing

/// The All, Used and Learned chips and the list order (WP-52). The server decides what a node is; the filters only
/// read its fields.
@Suite struct JourneyFilterTests {
    @Test func chipsAreAllUsedLearnedInThatOrder() {
        #expect(JourneyFilter.allCases == [.all, .used, .learned])
        #expect(JourneyFilter.allCases.map(\.title) == ["All", "Used", "Learned"])
        #expect(JourneyFilter.allCases.map(\.id) == ["all", "used", "learned"])
    }

    @Test func allShowsEveryNode() throws {
        let graph = try journeyFixtureGraph()
        #expect(graph.nodes(matching: .all) == graph.nodes)
        #expect(graph.count(.all) == 9)
    }

    @Test func usedMeansTheAgentUsedTheSkill() throws {
        let graph = try journeyFixtureGraph()
        let ids = Set(graph.nodes(matching: .used).map(\.id))
        #expect(ids == ["backup-cron-fix", "ssh-hardening", "arxiv-search", "paper-summary", "legacy-notes"])
        #expect(graph.count(.used) == 5)
    }

    @Test func learnedMeansTheAgentWroteTheSkill() throws {
        let graph = try journeyFixtureGraph()
        let ids = Set(graph.nodes(matching: .learned).map(\.id))
        #expect(ids == ["backup-cron-fix", "systemd-service-patterns", "paper-summary"])
        #expect(graph.count(.learned) == 3)
    }

    @Test func memoryChunksShowUnderAllOnly() throws {
        let graph = try journeyFixtureGraph()
        let chunks = graph.nodes.filter { $0.kind == .memory }
        #expect(chunks.count == 3)
        #expect(chunks.allSatisfy { JourneyFilter.all.matches($0) })
        #expect(chunks.allSatisfy { !JourneyFilter.used.matches($0) && !JourneyFilter.learned.matches($0) })
    }

    @Test func aSkillCanBeUsedAndLearnedAtOnce() {
        let node = JourneyNode(id: "x", useCount: 2, createdBy: "agent")
        #expect(JourneyFilter.used.matches(node) && JourneyFilter.learned.matches(node))
        let bundled = JourneyNode(id: "y", useCount: 0, createdBy: nil)
        #expect(!JourneyFilter.used.matches(bundled) && !JourneyFilter.learned.matches(bundled))
    }

    @Test func listIsNewestFirstThenUndatedByName() throws {
        let graph = try journeyFixtureGraph()
        #expect(
            graph.listed(.all).map(\.id) == [
                "backup-cron-fix", "memory:memory:1:a81d7e04", "paper-summary", "systemd-service-patterns",
                "ssh-hardening", "memory:memory:0:3f9a1c2b", "arxiv-search", "memory:profile:0:51c0be77",
                "legacy-notes",
            ])
        #expect(graph.listed(.learned).map(\.id) == ["backup-cron-fix", "paper-summary", "systemd-service-patterns"])
    }

    @Test func equalTimesFallBackToTheName() {
        let graph = JourneyGraph(nodes: [
            JourneyNode(id: "b", label: "banana", timestamp: 5), JourneyNode(id: "a", label: "Apple", timestamp: 5),
            JourneyNode(id: "c", label: "cherry", timestamp: 5),
        ])
        #expect(graph.listed(.all).map(\.id) == ["a", "b", "c"])
    }

    @Test func emptyGraphListsNothing() {
        let graph = JourneyGraph()
        #expect(graph.listed(.all).isEmpty && graph.nodes(matching: .used).isEmpty && graph.count(.learned) == 0)
    }
}
