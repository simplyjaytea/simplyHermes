import Foundation

/// A made-up learning graph for previews, snapshot tests and the demo launch route. It has several categories, nodes
/// with no time, an archived and a stale skill, a pinned skill and links from memory chunks to skills, so every state
/// of the screen shows up in it. Nothing here is real user data.
public enum JourneySample {
    /// The sample graph: 26 nodes, 14 links.
    public static let graph: JourneyGraph = {
        let nodes = skills.map(\.node) + memories.map(\.node)
        var counts: [String: Int] = [:]
        for node in nodes { counts[node.category, default: 0] += 1 }
        let clusters = counts.map { JourneyCluster(category: $0.key, count: $0.value) }
            .sorted { $0.count == $1.count ? $0.category < $1.category : $0.count > $1.count }
        let cards = memories.map {
            JourneyMemoryCard(source: $0.source, title: $0.title, body: $0.body, fingerprint: $0.fingerprint)
        }
        let stats: [String: JSONValue] = [
            "nodes": .int(nodes.count), "related_edges": .int(edges.count), "categories": .int(counts.count),
            "agent_created": .int(nodes.filter(\.isLearned).count),
        ]
        return JourneyGraph(nodes: nodes, edges: edges, clusters: clusters, memory: cards, stats: stats)
    }()

    /// The text a node opens with, in the shape the server sends: a whole `SKILL.md`, or the raw memory chunk.
    public static func content(for id: String) -> String? {
        if let skill = skills.first(where: { $0.node.id == id }) { return skill.document }
        return memories.first { $0.node.id == id }?.body
    }

    /// When the sample starts, in Unix seconds: the middle of 2026. Fixed so snapshots do not drift.
    private static let origin = 1_780_000_000.0

    private static func time(day: Double?) -> Double? {
        day.map { origin + $0 * 86_400 }
    }

    private struct Skill {
        var node: JourneyNode
        var summary: String

        var document: String {
            """
            ---
            name: \(node.id)
            description: \(summary)
            ---

            # \(node.label)

            \(summary)

            1. Look at what the task needs before running anything.
            2. Do the smallest step that shows whether the plan works.
            3. Report what changed and what is left.
            """
        }
    }

    private struct Memory {
        var node: JourneyNode
        var source: String
        var title: String
        var body: String
        var fingerprint: String
    }

    /// One skill per line: name, category, day since the start, uses, who made it, state, pinned, summary.
    /// A dash means no day or no author.
    private static let skillTable = """
        docker-compose-debug | devops | 2 | 14 | agent | active | - | Find out why a compose stack will not start.
        ssh-hardening | devops | 9 | 3 | - | active | - | Lock down sshd on a new server.
        systemd-service-patterns | devops | 20 | 0 | - | stale | - | Unit file patterns that restart cleanly.
        backup-cron-fix | devops | 31 | 22 | learn | active | - | Repair a backup job that stopped running.
        nginx-reverse-proxy | devops | 47 | 6 | agent | active | - | Put a service behind nginx with TLS.
        arxiv-search | research | 4 | 31 | - | active | - | Search arXiv and rank the results.
        paper-summary | research | 12 | 9 | agent | active | - | Summarise a paper in five lines.
        citation-check | research | 33 | 0 | - | archived | - | Check that a citation says what is claimed.
        literature-matrix | research | 58 | 2 | learn | active | - | Compare papers in one table.
        swift-concurrency-review | software | 6 | 18 | agent | active | pinned | Review Swift code for races.
        git-bisect-helper | software | 15 | 5 | - | active | - | Narrow down the commit that broke a test.
        pr-description-writer | software | 26 | 12 | learn | active | - | Write a pull request description.
        xcodegen-project-fixes | software | 40 | 4 | agent | active | - | Fix common XcodeGen project errors.
        test-flake-hunter | software | 66 | 1 | learn | active | - | Find the cause of a flaky test.
        svg-diagrams | creative | 8 | 7 | - | active | - | Draw a simple diagram as SVG.
        color-palette-picker | creative | 22 | 0 | - | active | - | Pick a colour palette for a brief.
        icon-brief | creative | 52 | 2 | agent | active | - | Write a brief for an app icon.
        daily-standup | productivity | 11 | 25 | - | active | - | Draft a standup from yesterday's work.
        calendar-triage | productivity | 29 | 8 | learn | active | - | Sort the week's invitations.
        inbox-zero | productivity | 44 | 0 | - | stale | - | Clear an inbox in one pass.
        legacy-notes | productivity | - | 1 | - | active | - | Notes from before the graph kept dates.
        """

    private static let skills: [Skill] = skillTable.split(separator: "\n").compactMap { line in
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count == 8 else { return nil }
        let node = JourneyNode(
            id: cells[0], kind: .skill, timestamp: time(day: Double(cells[2])), category: cells[1],
            useCount: Int(cells[3]) ?? 0, state: cells[5], createdBy: cells[4] == "-" ? nil : cells[4],
            pinned: cells[6] == "pinned")
        return Skill(node: node, summary: cells[7])
    }

    private static func memory(
        _ source: String, _ index: Int, _ fingerprint: String, day: Double?, body: String
    ) -> Memory {
        let title = body.split(separator: "\n").first.map(String.init) ?? body
        return Memory(
            node: JourneyNode(
                id: "memory:\(source):\(index):\(fingerprint)", label: title, kind: .memory, memorySource: source,
                timestamp: time(day: day), category: "memory", createdBy: "memory"),
            source: source, title: title, body: body, fingerprint: fingerprint)
    }

    private static let memories: [Memory] = [
        memory("memory", 0, "3f9a1c2b", day: 3, body: "JT likes short answers.\nSkip the recap at the end."),
        memory("memory", 1, "a81d7e04", day: 18, body: "Hermes runs on the studio Mac.\nIt restarts after updates."),
        memory("profile", 0, "51c0be77", day: 5, body: "JT uses an iPhone Duo.\nThe outer screen is for quick checks."),
        memory("profile", 1, "9d2e4a10", day: 36, body: "JT works in UTC+2.\nSchedule jobs for the morning."),
        memory("memory", 2, "77aa0e12", day: nil, body: "An older note with no date."),
    ]

    private static let edges: [JourneyEdge] = [
        ("docker-compose-debug", "nginx-reverse-proxy"), ("backup-cron-fix", "systemd-service-patterns"),
        ("backup-cron-fix", "ssh-hardening"), ("arxiv-search", "paper-summary"),
        ("paper-summary", "literature-matrix"), ("paper-summary", "citation-check"),
        ("swift-concurrency-review", "git-bisect-helper"), ("pr-description-writer", "git-bisect-helper"),
        ("xcodegen-project-fixes", "test-flake-hunter"), ("daily-standup", "calendar-triage"),
        ("memory:memory:1:a81d7e04", "ssh-hardening"), ("memory:profile:0:51c0be77", "xcodegen-project-fixes"),
        ("memory:memory:0:3f9a1c2b", "daily-standup"), ("svg-diagrams", "icon-brief"),
    ].map { JourneyEdge(source: $0.0, target: $0.1) }
}

/// A ``JourneyBackend`` that serves a sample graph from memory, with edits and deletes that behave like the server's:
/// a skill is archived and stays in the graph, a memory chunk is removed, and a pinned skill is refused. For previews,
/// the demo launch route and tests.
public actor SampleJourneyBackend: JourneyBackend {
    private var graph: JourneyGraph
    private var edited: [String: String] = [:]

    /// Creates a backend that starts from `graph`.
    public init(graph: JourneyGraph = JourneySample.graph) {
        self.graph = graph
    }

    public func learningGraph() async throws -> JourneyGraph { graph }

    public func learningNode(id: String) async throws -> JourneyNodeDetail {
        guard let node = graph.node(id: id), let content = edited[id] ?? JourneySample.content(for: id) else {
            throw RESTError.http(status: 404, detail: "No such node: \(id)")
        }
        return JourneyNodeDetail(kind: node.kind, id: id, label: node.label, content: content)
    }

    public func updateLearningNode(id: String, content: String) async throws -> JourneyMutationResult {
        guard graph.node(id: id) != nil else { throw RESTError.http(status: 404, detail: "No such node: \(id)") }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RESTError.http(status: 400, detail: "The content cannot be empty.")
        }
        edited[id] = content
        return JourneyMutationResult(ok: true, message: "Saved \(id).")
    }

    public func deleteLearningNode(id: String) async throws -> JourneyMutationResult {
        guard var node = graph.node(id: id) else { throw RESTError.http(status: 404, detail: "No such node: \(id)") }
        if node.pinned { throw RESTError.http(status: 409, detail: "\(id) is pinned. Unpin it before deleting.") }
        var nodes = graph.nodes
        if node.kind == .skill {
            node.state = "archived"
            nodes = nodes.map { $0.id == id ? node : $0 }
        } else {
            nodes.removeAll { $0.id == id }
        }
        graph = JourneyGraph(
            nodes: nodes, edges: graph.edges, clusters: graph.clusters, memory: graph.memory, stats: graph.stats)
        let message =
            node.kind == .skill
            ? "archived '\(id)' — restore with: hermes curator restore \(id)" : "Removed the memory chunk."
        return JourneyMutationResult(ok: true, message: message)
    }
}
