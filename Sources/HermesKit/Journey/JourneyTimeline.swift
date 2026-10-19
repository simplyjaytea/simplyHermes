import Foundation

/// The timeline behind the scrubber: when each node came to be, and which nodes existed at a point in time.
///
/// A scrub position runs from 0 (the oldest node) to 1 (now, everything). Each node gets a `recency` on the same
/// scale, a straight map of its timestamp between the oldest and newest known one, like the Desktop map's radial time
/// axis. Two cases fall back so the scrubber always has something to reveal:
/// - A node with no timestamp counts as always there (recency 0).
/// - When fewer than two different timestamps exist, there is no real time span, so nodes are ordered by timestamp
///   and name and spread evenly. The scrubber then steps through them one by one and shows no dates.
public struct JourneyTimeline: Sendable, Equatable {
    private let recencies: [String: Double]
    private let ordered: [String]
    private let earliest: Double?
    private let latest: Double?

    /// Orders `nodes` in time. The order of the list does not matter.
    public init(nodes: [JourneyNode]) {
        let known = nodes.compactMap(\.timestamp)
        let low = known.min()
        let high = known.max()
        let sorted = nodes.sorted { left, right in
            let leftTime = left.timestamp ?? -.infinity
            let rightTime = right.timestamp ?? -.infinity
            return leftTime == rightTime ? left.id < right.id : leftTime < rightTime
        }
        var map: [String: Double] = [:]
        if let low, let high, high > low {
            for node in nodes {
                map[node.id] = node.timestamp.map { ($0 - low) / (high - low) } ?? 0
            }
            earliest = low
            latest = high
        } else {
            let steps = Double(max(sorted.count - 1, 1))
            for (index, node) in sorted.enumerated() { map[node.id] = Double(index) / steps }
            earliest = nil
            latest = nil
        }
        recencies = map
        ordered = sorted.map(\.id)
    }

    /// Node ids, oldest first.
    public var orderedIDs: [String] { ordered }

    /// True when the scrubber maps to real dates. False for a graph with no time span.
    public var hasDates: Bool { earliest != nil }

    /// The oldest known timestamp.
    public var start: Date? { earliest.map { Date(timeIntervalSince1970: $0) } }

    /// The newest known timestamp.
    public var end: Date? { latest.map { Date(timeIntervalSince1970: $0) } }

    /// Where a node sits on the scale from 0 (oldest) to 1 (newest). Unknown ids give 1.
    public func recency(of id: String) -> Double { recencies[id] ?? 1 }

    /// True when the node existed at scrub position `position`.
    public func isVisible(_ id: String, at position: Double) -> Bool {
        recency(of: id) <= Self.clamp(position) + 1e-9
    }

    /// The ids that existed at scrub position `position`, oldest first.
    public func visibleIDs(at position: Double) -> [String] {
        ordered.filter { isVisible($0, at: position) }
    }

    /// The moment a scrub position stands for. Nil when the graph has no time span.
    public func date(at position: Double) -> Date? {
        guard let earliest, let latest else { return nil }
        return Date(timeIntervalSince1970: earliest + Self.clamp(position) * (latest - earliest))
    }

    /// The scrub position of a moment, clamped to the graph's span. Nil when the graph has no time span.
    public func position(of date: Date) -> Double? {
        guard let earliest, let latest else { return nil }
        return Self.clamp((date.timeIntervalSince1970 - earliest) / (latest - earliest))
    }

    /// Keeps a scrub position inside 0 to 1. Not-a-number gives 1, the whole graph.
    public static func clamp(_ position: Double) -> Double {
        position.isNaN ? 1 : min(max(position, 0), 1)
    }
}
