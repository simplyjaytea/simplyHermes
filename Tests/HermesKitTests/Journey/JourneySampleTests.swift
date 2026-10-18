import Foundation
import HermesKit
import Testing

/// The sample graph and the in-memory backend behind previews and the demo route (WP-52).
@Suite struct JourneySampleTests {
    @Test func sampleGraphHangsTogether() {
        let graph = JourneySample.graph
        let ids = graph.nodes.map(\.id)
        #expect(ids.count == 26 && Set(ids).count == 26)
        #expect(graph.skillCount == 21 && graph.memoryCount == 5 && graph.edges.count == 14)
        #expect(graph.edges.allSatisfy { ids.contains($0.source) && ids.contains($0.target) })
        #expect(graph.clusters.reduce(0) { $0 + $1.count } == 26)
        #expect(graph.memory.count == 5)
        #expect(graph.nodes.filter { $0.kind == .memory }.allSatisfy { $0.id.hasPrefix("memory:") })
        #expect(ids.allSatisfy { JourneySample.content(for: $0)?.isEmpty == false })
        #expect(JourneySample.content(for: "no-such-node") == nil)
    }

    @Test func sampleShowsEveryStateTheScreenDraws() {
        let nodes = JourneySample.graph.nodes
        #expect(nodes.contains { $0.state == "archived" } && nodes.contains { $0.state == "stale" })
        #expect(nodes.contains { $0.pinned } && nodes.contains { $0.timestamp == nil })
        #expect(nodes.contains { $0.isLearned } && nodes.contains { $0.isUsed && !$0.isLearned })
        #expect(nodes.contains { $0.memorySource == "profile" } && nodes.contains { $0.memorySource == "memory" })
        #expect(Set(nodes.map(\.category)).count >= 5)
        #expect(JourneySample.graph.listed(.learned).count == JourneySample.graph.count(.learned))
    }

    @Test func sampleSurvivesAJSONRoundTrip() throws {
        let data = try JSONEncoder().encode(JourneySample.graph)
        let back = try JSONDecoder().decode(JourneyGraph.self, from: data)
        #expect(back == JourneySample.graph)
    }

    @Test func backendServesTheGraphAndNodeText() async throws {
        let backend = SampleJourneyBackend()
        #expect(try await backend.learningGraph() == JourneySample.graph)
        let detail = try await backend.learningNode(id: "backup-cron-fix")
        #expect(detail.kind == .skill && detail.content.hasPrefix("---\nname: backup-cron-fix"))
        await #expect(throws: RESTError.http(status: 404, detail: "No such node: nope")) {
            try await backend.learningNode(id: "nope")
        }
    }

    @Test func editsAreKept() async throws {
        let backend = SampleJourneyBackend()
        let result = try await backend.updateLearningNode(id: "backup-cron-fix", content: "# Changed")
        #expect(result.ok == true)
        #expect(try await backend.learningNode(id: "backup-cron-fix").content == "# Changed")
        await #expect(throws: RESTError.http(status: 400, detail: "The content cannot be empty.")) {
            try await backend.updateLearningNode(id: "backup-cron-fix", content: " \n")
        }
        await #expect(throws: RESTError.self) { try await backend.updateLearningNode(id: "nope", content: "x") }
    }

    @Test func deletingASkillArchivesItAndAMemoryChunkIsRemoved() async throws {
        let backend = SampleJourneyBackend()
        let archived = try await backend.deleteLearningNode(id: "backup-cron-fix")
        #expect(archived.message?.hasPrefix("archived 'backup-cron-fix'") == true)
        var graph = try await backend.learningGraph()
        #expect(graph.node(id: "backup-cron-fix")?.state == "archived" && graph.nodes.count == 26)

        let removed = try await backend.deleteLearningNode(id: "memory:profile:1:9d2e4a10")
        #expect(removed.ok == true)
        graph = try await backend.learningGraph()
        #expect(graph.node(id: "memory:profile:1:9d2e4a10") == nil && graph.nodes.count == 25)
    }

    @Test func aPinnedSkillCannotBeDeleted() async throws {
        let backend = SampleJourneyBackend()
        await #expect(
            throws: RESTError.http(
                status: 409, detail: "swift-concurrency-review is pinned. Unpin it before deleting.")
        ) {
            try await backend.deleteLearningNode(id: "swift-concurrency-review")
        }
        #expect(try await backend.learningGraph() == JourneySample.graph)
    }
}
