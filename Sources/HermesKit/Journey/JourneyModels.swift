import Foundation

// Models for the learning graph behind Memory > Graph (WP-52), the "Journey" of upstream Hermes.
//
// `docs/protocol/dashboard-openapi.json` leaves the answers of `/api/learning/*` open (`{}`), so the shape here comes
// from reading upstream `agent/learning_graph.py` and `agent/learning_mutations.py`: a skill node and a memory-chunk
// node share one object shape with camelCase keys, and the graph adds `edges`, `clusters`, `memory` and `stats`.
// Every field is decoded loosely: a missing or odd value falls back to a default, and one broken node or edge is
// dropped instead of failing the whole graph.

/// What a node of the learning graph is.
public enum JourneyNodeKind: Sendable, Hashable {
    /// A skill the agent learned or used.
    case skill
    /// A chunk of `MEMORY.md` or `USER.md`.
    case memory
    /// A kind a newer server sends.
    case other(String)

    /// Creates a kind from the server's `kind` text.
    public init(rawValue: String) {
        switch rawValue {
        case "skill": self = .skill
        case "memory": self = .memory
        default: self = .other(rawValue)
        }
    }

    /// The server's `kind` text.
    public var rawValue: String {
        switch self {
        case .skill: "skill"
        case .memory: "memory"
        case .other(let value): value
        }
    }
}

extension JourneyNodeKind: Codable {
    /// Decodes the `kind` text.
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    /// Encodes the `kind` text.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// One node of the learning graph: a learned or used skill, or a chunk of the agent's memory files.
public struct JourneyNode: Sendable, Hashable, Codable, Identifiable {
    /// The skill name, or `memory:<source>:<index>:<fingerprint>` for a memory chunk. Pass it back to read, edit or
    /// delete the node.
    public var id: String
    /// Name to show.
    public var label: String
    /// Skill or memory chunk.
    public var kind: JourneyNodeKind
    /// For a memory chunk: `memory` (`MEMORY.md`) or `profile` (`USER.md`).
    public var memorySource: String?
    /// Unix time in seconds when the node was last touched, if the server knows it.
    public var timestamp: Double?
    /// The skill's category, or `memory` for a memory chunk.
    public var category: String
    /// How often the agent used the skill.
    public var useCount: Int
    /// `active`, `stale` or `archived`.
    public var state: String
    /// Who made the skill: `agent` or `learn` for skills the agent wrote itself, `memory` for memory chunks.
    public var createdBy: String?
    /// True when the skill is pinned. The server refuses to delete a pinned skill.
    public var pinned: Bool

    /// Creates a node. A missing `label` is the id.
    public init(
        id: String, label: String? = nil, kind: JourneyNodeKind = .skill, memorySource: String? = nil,
        timestamp: Double? = nil, category: String = "", useCount: Int = 0, state: String = "active",
        createdBy: String? = nil, pinned: Bool = false
    ) {
        self.id = id
        self.label = label ?? id
        self.kind = kind
        self.memorySource = memorySource
        self.timestamp = timestamp
        self.category = category
        self.useCount = useCount
        self.state = state
        self.createdBy = createdBy
        self.pinned = pinned
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, kind, memorySource, timestamp, category, useCount, state, createdBy, pinned
    }

    /// Decodes a node. Only `id` is required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        self.id = id
        label = container.looseString(.label) ?? id
        kind = JourneyNodeKind(rawValue: container.looseString(.kind) ?? "skill")
        memorySource = container.looseString(.memorySource)
        timestamp = Self.seconds(fromTimestamp: container.looseDouble(.timestamp))
        category = container.looseString(.category) ?? ""
        useCount = max(0, container.looseInt(.useCount) ?? 0)
        state = container.looseString(.state) ?? "active"
        createdBy = container.looseString(.createdBy)
        pinned = container.looseBool(.pinned) ?? false
    }

    /// Unix seconds from a server timestamp. A value of zero or less means "unknown", and a value too large to be
    /// seconds (after the year 5000) is read as milliseconds.
    private static func seconds(fromTimestamp value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value > 95_000_000_000 ? value / 1000 : value
    }

    /// The skill was written by the agent itself (`createdBy` is `agent` or `learn`). Memory chunks never are.
    public var isLearned: Bool { createdBy == "agent" || createdBy == "learn" }

    /// The agent used the skill at least once.
    public var isUsed: Bool { useCount > 0 }

    /// True for a skill that was archived or went stale, drawn smaller and fainter.
    public var isDimmed: Bool { state == "archived" || state == "stale" }

    /// When the node was last touched.
    public var date: Date? { timestamp.map { Date(timeIntervalSince1970: $0) } }
}

/// A declared link between two nodes: `related_skills` of a skill, or a memory chunk that mentions a skill.
public struct JourneyEdge: Sendable, Hashable, Codable {
    /// Id of the first node.
    public var source: String
    /// Id of the second node.
    public var target: String

    /// Creates an edge.
    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// How many nodes a category holds.
public struct JourneyCluster: Sendable, Hashable, Codable {
    /// Category name, or `memory`.
    public var category: String
    /// Nodes in it.
    public var count: Int

    /// Creates a cluster.
    public init(category: String, count: Int) {
        self.category = category
        self.count = count
    }
}

/// A memory chunk as the server lists it under `memory`. The same chunk also appears as a node.
public struct JourneyMemoryCard: Sendable, Hashable, Codable {
    /// `memory` or `profile`.
    public var source: String
    /// First line.
    public var title: String
    /// The whole chunk.
    public var body: String
    /// Short digest of the text, carried in the node id.
    public var fingerprint: String?

    /// Creates a card.
    public init(source: String, title: String, body: String, fingerprint: String? = nil) {
        self.source = source
        self.title = title
        self.body = body
        self.fingerprint = fingerprint
    }
}

/// `GET /api/learning/graph`: the learned skills and memory chunks of one profile.
public struct JourneyGraph: Sendable, Equatable, Codable {
    /// Skills and memory chunks, with duplicate ids removed.
    public var nodes: [JourneyNode]
    /// Links between nodes. May name nodes the list does not hold; the scene skips those.
    public var edges: [JourneyEdge]
    /// Node counts per category.
    public var clusters: [JourneyCluster]
    /// Memory chunks.
    public var memory: [JourneyMemoryCard]
    /// Free-form counts such as `nodes`, `related_edges` and `agent_created`.
    public var stats: [String: JSONValue]

    /// Creates a graph.
    public init(
        nodes: [JourneyNode] = [], edges: [JourneyEdge] = [], clusters: [JourneyCluster] = [],
        memory: [JourneyMemoryCard] = [], stats: [String: JSONValue] = [:]
    ) {
        self.nodes = Self.unique(nodes)
        self.edges = edges
        self.clusters = clusters
        self.memory = memory
        self.stats = stats
    }

    private enum CodingKeys: String, CodingKey {
        case nodes, edges, clusters, memory, stats
    }

    /// Decodes a graph. A missing list is empty and an element that does not decode is dropped.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = Self.unique(container.lossyList(JourneyNode.self, forKey: .nodes))
        edges = container.lossyList(JourneyEdge.self, forKey: .edges)
        clusters = container.lossyList(JourneyCluster.self, forKey: .clusters)
        memory = container.lossyList(JourneyMemoryCard.self, forKey: .memory)
        stats = (try? container.decode([String: JSONValue].self, forKey: .stats)) ?? [:]
    }

    /// The node with `id`.
    public func node(id: String) -> JourneyNode? { nodes.first { $0.id == id } }

    /// Number of skill nodes.
    public var skillCount: Int { nodes.filter { $0.kind == .skill }.count }

    /// Number of memory-chunk nodes.
    public var memoryCount: Int { nodes.filter { $0.kind == .memory }.count }

    private static func unique(_ nodes: [JourneyNode]) -> [JourneyNode] {
        var seen = Set<String>()
        return nodes.filter { seen.insert($0.id).inserted }
    }
}

/// `GET /api/learning/node`: the full text of a node, for the edit prefill.
public struct JourneyNodeDetail: Sendable, Equatable, Codable {
    /// Skill or memory chunk.
    public var kind: JourneyNodeKind?
    /// The node id.
    public var id: String?
    /// First line or skill name.
    public var label: String?
    /// The whole `SKILL.md` for a skill, or the raw chunk for a memory.
    public var content: String

    /// Creates a detail.
    public init(kind: JourneyNodeKind? = nil, id: String? = nil, label: String? = nil, content: String) {
        self.kind = kind
        self.id = id
        self.label = label
        self.content = content
    }

    private enum CodingKeys: String, CodingKey {
        case kind, id, label, content
    }

    /// Decodes a detail. `content` is required: an empty prefill could wipe the node on save.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = container.looseString(.kind).map(JourneyNodeKind.init(rawValue:))
        id = container.looseString(.id)
        label = container.looseString(.label)
        content = try container.decode(String.self, forKey: .content)
    }
}

/// The answer to an edit or a delete. A success status is a success unless the body says `"ok": false`.
public struct JourneyMutationResult: Sendable, Equatable {
    /// The server's `ok` flag, when it sends one.
    public var ok: Bool?
    /// What the server did, such as `archived 'x' — restore with: hermes curator restore x`.
    public var message: String?

    /// Creates a result.
    public init(ok: Bool? = nil, message: String? = nil) {
        self.ok = ok
        self.message = message
    }

    /// Reads `ok` (or `success`) and `message` from a JSON object body. Anything else gives an empty result.
    public init(body: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            self.init()
            return
        }
        let flag = (object["ok"] as? Bool) ?? (object["success"] as? Bool)
        let text = object["message"] as? String
        self.init(ok: flag, message: text?.isEmpty == true ? nil : text)
    }
}

// MARK: - Loose decoding

/// Wraps an element so a list keeps going past one that does not decode.
private struct Lossy<Element: Decodable>: Decodable {
    var element: Element?

    init(from decoder: any Decoder) throws {
        element = try? Element(from: decoder)
    }
}

extension KeyedDecodingContainer {
    /// The elements of a list that decode, or an empty list when the key is missing or not a list.
    func lossyList<Element: Decodable>(_ type: Element.Type, forKey key: Key) -> [Element] {
        guard let wrapped = try? decode([Lossy<Element>].self, forKey: key) else { return [] }
        return wrapped.compactMap(\.element)
    }

    /// A string, or a number written as text. Nil for anything else.
    func looseString(_ key: Key) -> String? {
        if let text = try? decode(String.self, forKey: key) { return text }
        if let number = try? decode(Int.self, forKey: key) { return String(number) }
        return nil
    }

    /// A number, or text holding one.
    func looseDouble(_ key: Key) -> Double? {
        if let number = try? decode(Double.self, forKey: key) { return number.isFinite ? number : nil }
        if let text = try? decode(String.self, forKey: key), let number = Double(text) {
            return number.isFinite ? number : nil
        }
        return nil
    }

    /// A whole number, a fraction rounded down, or text holding a number.
    func looseInt(_ key: Key) -> Int? {
        if let number = try? decode(Int.self, forKey: key) { return number }
        guard let number = looseDouble(key), abs(number) < 1e15 else { return nil }
        return Int(number.rounded(.down))
    }

    /// A boolean, a number (non-zero is true), or the text `true` or `false`.
    func looseBool(_ key: Key) -> Bool? {
        if let flag = try? decode(Bool.self, forKey: key) { return flag }
        if let number = try? decode(Int.self, forKey: key) { return number != 0 }
        guard let text = try? decode(String.self, forKey: key) else { return nil }
        switch text.lowercased() {
        case "true", "yes", "1": return true
        case "false", "no", "0": return false
        default: return nil
        }
    }
}
