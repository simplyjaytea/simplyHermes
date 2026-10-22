import Foundation

/// The All, Used and Learned chips (plan WP-52).
///
/// The server decides what a node is, so the filters read its fields and add no rule of their own:
/// - Used: the agent used the skill at least once (`useCount > 0`).
/// - Learned: the agent wrote the skill itself (`createdBy` is `agent` or `learn`), the same test the Desktop map uses
///   for its "learned" badge and the server uses to put a skill in the graph.
/// - Memory chunks (`createdBy` is `memory`, `useCount` is 0) belong to neither, so they show under All only.
public enum JourneyFilter: String, Sendable, Hashable, CaseIterable, Identifiable, Codable {
    /// Every node.
    case all
    /// Skills the agent used.
    case used
    /// Skills the agent wrote itself.
    case learned

    /// The chip id, for `ForEach`.
    public var id: String { rawValue }

    /// The chip text.
    public var title: String {
        switch self {
        case .all: "All"
        case .used: "Used"
        case .learned: "Learned"
        }
    }

    /// True when `node` stays visible under this filter.
    public func matches(_ node: JourneyNode) -> Bool {
        switch self {
        case .all: true
        case .used: node.isUsed
        case .learned: node.isLearned
        }
    }
}

extension JourneyGraph {
    /// The nodes that stay visible under `filter`, in server order.
    public func nodes(matching filter: JourneyFilter) -> [JourneyNode] {
        nodes.filter(filter.matches)
    }

    /// The nodes under `filter` for the list: newest first, then nodes with no time, ties broken by name.
    public func listed(_ filter: JourneyFilter) -> [JourneyNode] {
        nodes(matching: filter).sorted { left, right in
            switch (left.timestamp, right.timestamp) {
            case (let newer?, let older?) where newer != older: return newer > older
            case (.some, nil): return true
            case (nil, .some): return false
            default: return left.label.localizedCaseInsensitiveCompare(right.label) == .orderedAscending
            }
        }
    }

    /// How many nodes each filter shows, for the chip counts.
    public func count(_ filter: JourneyFilter) -> Int {
        nodes.filter(filter.matches).count
    }
}

extension JourneyNode {
    /// `Skill`, `Memory` or the server's own word for a newer kind.
    public var kindTitle: String {
        switch kind {
        case .skill: "Skill"
        case .memory: memorySource == "profile" ? "Profile memory" : "Memory"
        case .other(let value): value.capitalized
        }
    }

    /// Short facts for a list row, such as `Skill · devops · Learned · Used 7 times`.
    public var detailParts: [String] {
        var parts = [kindTitle]
        if kind == .skill, !category.isEmpty { parts.append(category) }
        if isLearned { parts.append("Learned") }
        if pinned { parts.append("Pinned") }
        if isDimmed { parts.append(state.capitalized) }
        if isUsed { parts.append(useCount == 1 ? "Used once" : "Used \(useCount) times") }
        return parts
    }
}
