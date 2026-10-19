import Foundation
import HermesKit

/// The hand-written graph fixture (`Fixtures/rest/learning_graph.json`), decoded the way the REST client decodes.
func journeyFixtureGraph() throws -> JourneyGraph {
    try decodeJourneyGraph(try restFixture("learning_graph"))
}

/// Decodes a graph from JSON text with the REST client's key strategy.
func decodeJourneyGraph(_ json: String) throws -> JourneyGraph {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(JourneyGraph.self, from: Data(json.utf8))
}

/// A small dated graph for timeline and layout tests: three skills in two categories, one memory chunk, one skill with
/// no time. `old` is the oldest, `new` the newest.
func journeyDatedGraph() -> JourneyGraph {
    JourneyGraph(
        nodes: [
            JourneyNode(id: "old", timestamp: 1_000, category: "alpha", useCount: 4, createdBy: "agent"),
            JourneyNode(id: "mid", timestamp: 2_000, category: "alpha", useCount: 0),
            JourneyNode(id: "new", timestamp: 3_000, category: "beta", useCount: 1, state: "archived"),
            JourneyNode(
                id: "memory:memory:0:aa", label: "A note", kind: .memory, memorySource: "memory", timestamp: 1_500,
                category: "memory", createdBy: "memory"),
            JourneyNode(id: "undated", category: "beta"),
        ],
        edges: [
            JourneyEdge(source: "old", target: "mid"), JourneyEdge(source: "mid", target: "new"),
            JourneyEdge(source: "memory:memory:0:aa", target: "old"), JourneyEdge(source: "new", target: "missing"),
        ])
}

/// SplitMix64, so the fuzz tests give the same inputs on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
