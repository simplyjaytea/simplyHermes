import Foundation
import HermesKit
import Testing

/// Decoding of the learning graph (WP-52). The fixtures are written by hand from the upstream source, so these tests
/// also pin how loosely a real server's answer may differ before the screen breaks.
@Suite struct JourneyModelsTests {
    @Test func fixtureGraphDecodes() throws {
        let graph = try journeyFixtureGraph()
        #expect(graph.nodes.count == 9 && graph.skillCount == 6 && graph.memoryCount == 3)
        #expect(graph.edges.count == 4 && graph.clusters.count == 4 && graph.memory.count == 3)
        #expect(graph.stats["nodes"] == JSONValue.int(9))
        #expect(graph.stats.count == 7)

        let cron = try #require(graph.node(id: "backup-cron-fix"))
        #expect(cron.label == "backup-cron-fix" && cron.kind == .skill && cron.category == "devops")
        #expect(cron.useCount == 22 && cron.createdBy == "learn" && cron.state == "active" && !cron.pinned)
        #expect(cron.timestamp == 1_781_000_000 && cron.date == Date(timeIntervalSince1970: 1_781_000_000))
        #expect(cron.isLearned && cron.isUsed && !cron.isDimmed)

        let ssh = try #require(graph.node(id: "ssh-hardening"))
        let archived = try #require(graph.node(id: "paper-summary"))
        let stale = try #require(graph.node(id: "systemd-service-patterns"))
        let undated = try #require(graph.node(id: "legacy-notes"))
        #expect(ssh.pinned && archived.isDimmed && stale.isDimmed && undated.timestamp == nil)

        let note = try #require(graph.node(id: "memory:profile:0:51c0be77"))
        #expect(note.kind == .memory && note.memorySource == "profile" && note.createdBy == "memory")
        #expect(!note.isLearned && !note.isUsed)

        #expect(graph.memory.first?.fingerprint == "3f9a1c2b" && graph.memory.first?.source == "memory")
        #expect(graph.clusters.first == JourneyCluster(category: "devops", count: 3))
        #expect(graph.edges.first == JourneyEdge(source: "backup-cron-fix", target: "systemd-service-patterns"))
    }

    @Test func oddValuesFallBackAndBrokenElementsAreDropped() throws {
        let json = """
            {"nodes":[
              {"id":"text","label":"Text","kind":"skill","timestamp":"1780000000","useCount":"3","pinned":"true"},
              {"label":"no id"},
              {"id":"text","label":"duplicate"},
              {"id":"odd","kind":42,"timestamp":null,"useCount":-5,"state":null,"createdBy":7},
              "garbage",
              {"id":"millis","timestamp":1780000000000},
              {"id":"zero","timestamp":0},
              {"id":"fraction","useCount":2.9,"pinned":0},
              {"id":"nan","timestamp":"soon"}
            ],"edges":[{"source":"a","target":"b"},{"source":"a"},5],"clusters":"nope","memory":null}
            """
        let graph = try decodeJourneyGraph(json)
        #expect(graph.nodes.map(\.id) == ["text", "odd", "millis", "zero", "fraction", "nan"])
        let text = try #require(graph.node(id: "text"))
        #expect(text.label == "Text" && text.timestamp == 1_780_000_000 && text.useCount == 3 && text.pinned)
        let odd = try #require(graph.node(id: "odd"))
        #expect(odd.label == "odd" && odd.useCount == 0 && odd.state == "active" && odd.timestamp == nil)
        let millis = try #require(graph.node(id: "millis"))
        let zero = try #require(graph.node(id: "zero"))
        let fraction = try #require(graph.node(id: "fraction"))
        let soon = try #require(graph.node(id: "nan"))
        #expect(millis.timestamp == 1_780_000_000 && zero.timestamp == nil && soon.timestamp == nil)
        #expect(fraction.useCount == 2 && !fraction.pinned)
        #expect(graph.edges == [JourneyEdge(source: "a", target: "b")])
        #expect(graph.clusters.isEmpty && graph.memory.isEmpty && graph.stats.isEmpty)
    }

    @Test func missingListsGiveAnEmptyGraph() throws {
        #expect(try decodeJourneyGraph("{}").nodes.isEmpty)
        #expect(try decodeJourneyGraph(#"{"nodes":null,"edges":{}}"#).edges.isEmpty)
        #expect(throws: DecodingError.self) { _ = try decodeJourneyGraph("[]") }
    }

    @Test func nodeKindsKeepUnknownWords() throws {
        #expect(JourneyNodeKind(rawValue: "skill") == .skill && JourneyNodeKind(rawValue: "memory") == .memory)
        #expect(JourneyNodeKind(rawValue: "plugin") == .other("plugin"))
        #expect(JourneyNodeKind.other("plugin").rawValue == "plugin")
        let encoded = try JSONEncoder().encode(JourneyNodeKind.other("plugin"))
        #expect(String(bytes: encoded, encoding: .utf8) == #""plugin""#)
        #expect(try JSONDecoder().decode(JourneyNodeKind.self, from: Data(#""memory""#.utf8)) == .memory)
    }

    @Test func nodeDetailNeedsItsContent() throws {
        let decoder = JSONDecoder()
        let skill = try decoder.decode(JourneyNodeDetail.self, from: Data(try restFixture("learning_node_skill").utf8))
        #expect(skill.kind == .skill && skill.id == "backup-cron-fix" && skill.content.hasPrefix("---\nname:"))
        let memory = try decoder.decode(
            JourneyNodeDetail.self, from: Data(try restFixture("learning_node_memory").utf8))
        #expect(memory.kind == .memory && memory.content == "JT likes short answers.\nSkip the recap at the end.")
        #expect(throws: DecodingError.self) {
            try decoder.decode(JourneyNodeDetail.self, from: Data(#"{"ok":true,"id":"x"}"#.utf8))
        }
        let bare = try decoder.decode(JourneyNodeDetail.self, from: Data(#"{"content":""}"#.utf8))
        #expect(bare.content.isEmpty && bare.id == nil && bare.kind == nil)
    }

    @Test func mutationResultReadsWhatItCan() {
        let archived = JourneyMutationResult(body: Data(#"{"ok":true,"message":"archived 'x'"}"#.utf8))
        #expect(archived == JourneyMutationResult(ok: true, message: "archived 'x'"))
        #expect(JourneyMutationResult(body: Data(#"{"success":false}"#.utf8)) == JourneyMutationResult(ok: false))
        #expect(JourneyMutationResult(body: Data(#"{"ok":true,"message":""}"#.utf8)).message == nil)
        #expect(JourneyMutationResult(body: Data("[]".utf8)) == JourneyMutationResult())
        #expect(JourneyMutationResult(body: Data()) == JourneyMutationResult())
    }

    @Test func rowFactsReadAsShortParts() {
        let learned = JourneyNode(
            id: "a", category: "devops", useCount: 22, state: "archived", createdBy: "learn", pinned: true)
        #expect(learned.detailParts == ["Skill", "devops", "Learned", "Pinned", "Archived", "Used 22 times"])
        #expect(JourneyNode(id: "b", category: "x", useCount: 1).detailParts == ["Skill", "x", "Used once"])
        #expect(JourneyNode(id: "c").detailParts == ["Skill"])
        let profile = JourneyNode(id: "m", kind: .memory, memorySource: "profile", category: "memory")
        #expect(profile.detailParts == ["Profile memory"] && profile.kindTitle == "Profile memory")
        #expect(JourneyNode(id: "n", kind: .memory, memorySource: "memory").kindTitle == "Memory")
        #expect(JourneyNode(id: "o", kind: .other("plugin")).kindTitle == "Plugin")
    }

    @Test func duplicateIDsKeepTheFirstNode() {
        let graph = JourneyGraph(nodes: [JourneyNode(id: "a", label: "First"), JourneyNode(id: "a", label: "Second")])
        #expect(graph.nodes.count == 1 && graph.nodes.first?.label == "First")
    }
}
