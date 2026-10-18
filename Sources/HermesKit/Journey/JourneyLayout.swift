import Foundation

/// A stable 32-bit FNV-1a hash. Swift's own `hashValue` changes on every launch; layout codes and category colours
/// need a value that never does.
enum JourneyHash {
    /// The hash of a text, over its UTF-8 bytes.
    static func fnv1a(_ text: String) -> UInt32 {
        fnv1a(bytes: text.utf8)
    }

    /// The hash of a run of bytes.
    static func fnv1a(bytes: some Sequence<UInt8>) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in bytes {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return hash
    }
}

/// Where each node sits in layout space, a disk of radius 1 around the origin.
///
/// The automatic layout is radial and needs no random start, so it is the same every time for the same graph:
/// - Each category gets a wedge of the circle, wider for bigger categories. Skills come first, biggest category
///   first, and the memory chunks fill the last wedge. A wedge starts at twelve o'clock and runs clockwise.
/// - Distance from the centre is age, like the Desktop map: the oldest nodes sit near the middle and the newest on the
///   outer rim (see ``JourneyTimeline``). The distance grows with the square root of the age, because the rings near
///   the middle are short and most graphs have many early nodes.
/// - Inside a wedge the nodes go from oldest to newest along a spiral arm, which keeps neighbours apart.
/// - A last pass nudges apart nodes that still sit closer than ``minimumGap``.
public struct JourneyLayout: Sendable, Equatable {
    /// Node id to position.
    public var positions: [String: CGPoint]

    /// Creates a layout from positions.
    public init(positions: [String: CGPoint] = [:]) {
        self.positions = positions
    }

    /// Places `nodes` with the automatic radial layout.
    public static func radial(nodes: [JourneyNode], timeline: JourneyTimeline) -> JourneyLayout {
        let groups = Dictionary(grouping: nodes, by: Group.init(node:))
        let keys = groups.keys.sorted { left, right in
            if left.isMemory != right.isMemory { return !left.isMemory }
            let leftCount = groups[left]?.count ?? 0
            let rightCount = groups[right]?.count ?? 0
            return leftCount == rightCount ? left.name < right.name : leftCount > rightCount
        }
        let weights = keys.map { Double(groups[$0]?.count ?? 0) + 1.5 }
        let total = weights.reduce(0, +)
        var start = -Double.pi / 2
        var positions: [String: CGPoint] = [:]
        for (key, weight) in zip(keys, weights) {
            let width = 2 * Double.pi * weight / total
            let members = (groups[key] ?? []).sorted { left, right in
                let leftRecency = timeline.recency(of: left.id)
                let rightRecency = timeline.recency(of: right.id)
                return leftRecency == rightRecency ? left.id < right.id : leftRecency < rightRecency
            }
            for (index, node) in members.enumerated() {
                let along = (Double(index) + 0.5) / Double(members.count)
                let angle = start + width * (0.06 + 0.88 * along)
                let stagger = Double(index % 3 - 1) * 0.018
                let age = timeline.recency(of: node.id).squareRoot()
                let radius = min(max(0.12 + 0.84 * age + stagger, innerRadius), outerRadius)
                positions[node.id] = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            }
            start += width
        }
        return JourneyLayout(positions: separated(positions))
    }

    /// The closest two nodes may sit after the layout, in layout units: about 18 points on the outer screen at zoom 1.
    public static let minimumGap = 0.085
    /// No node sits nearer the centre than this.
    static let innerRadius = 0.06
    /// No node sits further from the centre than this.
    static let outerRadius = 0.98

    /// Nudges apart nodes closer than ``minimumGap``, until none are or the work budget runs out. Nodes are taken in
    /// id order, so the result does not depend on how the list arrived. A graph too dense to fit keeps some overlap.
    private static func separated(_ positions: [String: CGPoint]) -> [String: CGPoint] {
        let ids = positions.keys.sorted()
        guard ids.count > 1 else { return positions }
        var across = ids.map { Double(positions[$0]?.x ?? 0) }
        var down = ids.map { Double(positions[$0]?.y ?? 0) }
        let passes = min(24, max(1, 4_000_000 / (ids.count * ids.count)))
        for _ in 0..<passes {
            guard pushApart(&across, &down) else { break }
            keepInDisk(&across, &down)
        }
        var result: [String: CGPoint] = [:]
        for (index, id) in ids.enumerated() { result[id] = CGPoint(x: across[index], y: down[index]) }
        return result
    }

    /// One pass over all pairs. Returns false when no pair was closer than ``minimumGap``.
    private static func pushApart(_ across: inout [Double], _ down: inout [Double]) -> Bool {
        var moved = false
        for first in across.indices {
            for second in (first + 1)..<across.count {
                let horizontal = across[second] - across[first]
                let vertical = down[second] - down[first]
                let distance = (horizontal * horizontal + vertical * vertical).squareRoot()
                guard distance < minimumGap else { continue }
                // Two nodes on one spot part along a direction taken from their places in the list.
                let unitAcross = distance > 1e-9 ? horizontal / distance : cos(Double(first + second))
                let unitDown = distance > 1e-9 ? vertical / distance : sin(Double(first + second))
                let shift = (minimumGap - distance) / 2
                across[first] -= unitAcross * shift
                down[first] -= unitDown * shift
                across[second] += unitAcross * shift
                down[second] += unitDown * shift
                moved = true
            }
        }
        return moved
    }

    /// Pulls nodes that a push moved out of the disk, or onto its very centre, back between the two radii.
    private static func keepInDisk(_ across: inout [Double], _ down: inout [Double]) {
        for index in across.indices {
            let length = (across[index] * across[index] + down[index] * down[index]).squareRoot()
            let target = min(max(length, innerRadius), outerRadius)
            guard target != length else { continue }
            let factor = length > 1e-9 ? target / length : 0
            across[index] = length > 1e-9 ? across[index] * factor : target
            down[index] *= factor
        }
    }

    /// The wedge a node belongs to: memory chunks together, skills by category.
    private struct Group: Hashable {
        var isMemory: Bool
        var name: String

        init(node: JourneyNode) {
            isMemory = node.kind == .memory
            name = isMemory ? "memory" : (node.category.isEmpty ? "other" : node.category)
        }
    }
}

/// What part of the layout is on screen: how far in, and which layout point sits at the middle of the view.
///
/// Zoom 1 fits the whole disk in the view. The range is 0.5 to 8, and the centre cannot drift more than
/// ``reach`` away from the middle of the graph, so the graph can never be lost off screen.
public struct JourneyViewport: Sendable, Equatable {
    /// The zoom limits.
    public static let zoomRange: ClosedRange<Double> = 0.5...8
    /// The furthest the centre may drift from the middle of the graph, in layout units.
    public static let reach: Double = 1.25
    /// Zoom 1, centred: the whole graph.
    public static let fit = JourneyViewport()

    /// Zoom relative to fit. Clamped to ``zoomRange``.
    public private(set) var zoom: Double
    /// The layout point at the middle of the view. Clamped to ``reach``.
    public private(set) var center: CGPoint

    /// Creates a viewport. Out-of-range or not-a-number values are pulled back in range.
    public init(zoom: Double = 1, center: CGPoint = .zero) {
        self.zoom = Self.clampZoom(zoom)
        self.center = Self.clampCenter(center)
    }

    /// Pulls a zoom into ``zoomRange``. Not-a-number gives 1.
    public static func clampZoom(_ zoom: Double) -> Double {
        zoom.isNaN ? 1 : min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// Pulls a centre within ``reach`` of the origin. A not-a-number coordinate gives 0.
    public static func clampCenter(_ center: CGPoint) -> CGPoint {
        let horizontal = center.x.isFinite ? Double(center.x) : 0
        let vertical = center.y.isFinite ? Double(center.y) : 0
        let distance = (horizontal * horizontal + vertical * vertical).squareRoot()
        guard distance > reach else { return CGPoint(x: horizontal, y: vertical) }
        let factor = reach / distance
        return CGPoint(x: horizontal * factor, y: vertical * factor)
    }

    /// Points per layout unit at zoom 1 in a view of `size`.
    public func fitScale(in size: CGSize) -> Double {
        max(Double(min(size.width, size.height)), 1) / 2 * 0.88
    }

    /// Points per layout unit at the current zoom.
    public func scale(in size: CGSize) -> Double { fitScale(in: size) * zoom }

    /// The view point of a layout point.
    public func toView(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let factor = scale(in: size)
        return CGPoint(
            x: Double(size.width) / 2 + (Double(point.x) - Double(center.x)) * factor,
            y: Double(size.height) / 2 + (Double(point.y) - Double(center.y)) * factor)
    }

    /// The layout point under a view point.
    public func toLayout(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let factor = scale(in: size)
        return CGPoint(
            x: Double(center.x) + (Double(point.x) - Double(size.width) / 2) / factor,
            y: Double(center.y) + (Double(point.y) - Double(size.height) / 2) / factor)
    }

    /// Zooms by `factor` and keeps the layout point under `anchor` (a view point) where it is, like a pinch.
    public func zoomed(by factor: Double, around anchor: CGPoint, in size: CGSize) -> JourneyViewport {
        guard factor.isFinite, factor > 0 else { return self }
        let target = Self.clampZoom(zoom * factor)
        let held = toLayout(anchor, in: size)
        let newScale = fitScale(in: size) * target
        let moved = CGPoint(
            x: Double(held.x) - (Double(anchor.x) - Double(size.width) / 2) / newScale,
            y: Double(held.y) - (Double(anchor.y) - Double(size.height) / 2) / newScale)
        return JourneyViewport(zoom: target, center: moved)
    }

    /// Moves the view by a drag of `translation` points: the graph follows the finger.
    public func panned(by translation: CGSize, in size: CGSize) -> JourneyViewport {
        let factor = scale(in: size)
        return JourneyViewport(
            zoom: zoom,
            center: CGPoint(
                x: Double(center.x) - Double(translation.width) / factor,
                y: Double(center.y) - Double(translation.height) / factor))
    }

    /// Smooth start and finish for an animated move: 0 stays 0, 1 stays 1, and the speed is zero at both ends. Values
    /// outside 0 to 1 are pulled in; not-a-number counts as 1.
    public static func eased(_ progress: Double) -> Double {
        let clamped = min(max(progress.isNaN ? 1 : progress, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }

    /// A viewport `progress` of the way (0 to 1) to `target`, for an animated move. Zoom changes in steps of equal
    /// ratio, so a zoom-in feels even.
    public func interpolated(to target: JourneyViewport, progress: Double) -> JourneyViewport {
        let amount = min(max(progress.isNaN ? 1 : progress, 0), 1)
        let ratio = target.zoom / zoom
        return JourneyViewport(
            zoom: zoom * pow(ratio, amount),
            center: CGPoint(
                x: Double(center.x) + (Double(target.center.x) - Double(center.x)) * amount,
                y: Double(center.y) + (Double(target.center.y) - Double(center.y)) * amount))
    }
}

/// Everything the user can change about the graph view, and all a layout code carries (see ``JourneyLayoutCode``).
public struct JourneyLayoutState: Sendable, Equatable {
    /// Which nodes show.
    public var filter: JourneyFilter
    /// The scrub position, 0 to 1. 1 shows everything.
    public var scrub: Double
    /// Zoom and pan.
    public var viewport: JourneyViewport
    /// Nodes moved off the automatic layout, by node id. Empty unless a layout code placed some.
    public var placements: [String: CGPoint]

    /// Creates a state. The scrub position is kept inside 0 to 1.
    public init(
        filter: JourneyFilter = .all, scrub: Double = 1, viewport: JourneyViewport = .fit,
        placements: [String: CGPoint] = [:]
    ) {
        self.filter = filter
        self.scrub = JourneyTimeline.clamp(scrub)
        self.viewport = viewport
        self.placements = placements
    }
}

/// The nodes and links on screen for one filter and scrub position, with positions in layout space.
///
/// The model builds it when the graph, filter or scrub changes. Drawing only walks it.
public struct JourneyScene: Sendable, Equatable {
    /// One node to draw.
    public struct Node: Sendable, Equatable, Identifiable {
        /// The node id.
        public var id: String
        /// Name to show.
        public var label: String
        /// Skill or memory chunk.
        public var kind: JourneyNodeKind
        /// Position in layout space.
        public var position: CGPoint
        /// Dot radius in points at any zoom: bigger for skills the agent used a lot.
        public var radius: Double
        /// Colour slot, 0 to ``JourneyScene/paletteSize`` minus 1: 0 for memory chunks, 1 and up for skills, and the
        /// same slot for a category every time.
        public var paletteIndex: Int
        /// The agent wrote this skill itself.
        public var isLearned: Bool
        /// The skill is pinned.
        public var isPinned: Bool
        /// The skill is archived or stale.
        public var isDimmed: Bool
    }

    /// One line between two visible nodes.
    public struct Link: Sendable, Equatable {
        /// Position of the first node in layout space.
        public var source: CGPoint
        /// Position of the second node in layout space.
        public var target: CGPoint
    }

    /// How many category colours the palette has.
    public static let paletteSize = 8
    /// A scene with nothing in it.
    public static let empty = JourneyScene(nodes: [], links: [])

    /// The visible nodes, oldest first. Nodes of the same age go by id, so the order never changes between runs.
    public var nodes: [Node]
    /// Links whose two ends are both visible.
    public var links: [Link]

    /// Builds the scene: nodes that pass the filter and already existed at the scrub position, laid out by
    /// `layout` unless `state` placed them elsewhere.
    public static func make(
        graph: JourneyGraph, layout: JourneyLayout, timeline: JourneyTimeline, state: JourneyLayoutState
    ) -> JourneyScene {
        let visible = graph.nodes
            .filter { state.filter.matches($0) && timeline.isVisible($0.id, at: state.scrub) }
            .sorted { left, right in
                let leftRecency = timeline.recency(of: left.id)
                let rightRecency = timeline.recency(of: right.id)
                return leftRecency == rightRecency ? left.id < right.id : leftRecency < rightRecency
            }
        var positions: [String: CGPoint] = [:]
        var nodes: [Node] = []
        for node in visible {
            let position = state.placements[node.id] ?? layout.positions[node.id] ?? .zero
            positions[node.id] = position
            let bonus = min(Double(node.useCount).squareRoot() * 1.1, 8) + (node.pinned ? 1 : 0)
            nodes.append(
                Node(
                    id: node.id, label: node.label, kind: node.kind, position: position,
                    radius: (node.isDimmed ? 4.5 : 6) + bonus, paletteIndex: node.paletteIndex,
                    isLearned: node.isLearned, isPinned: node.pinned, isDimmed: node.isDimmed))
        }
        let links = graph.edges.compactMap { edge -> Link? in
            guard let source = positions[edge.source], let target = positions[edge.target] else { return nil }
            return Link(source: source, target: target)
        }
        return JourneyScene(nodes: nodes, links: links)
    }

    /// The visible node closest to a layout point, if one lies within `distance` layout units of it.
    public func node(near point: CGPoint, within distance: Double) -> Node? {
        var best: (node: Node, gap: Double)?
        for node in nodes {
            let horizontal = Double(node.position.x - point.x)
            let vertical = Double(node.position.y - point.y)
            let gap = (horizontal * horizontal + vertical * vertical).squareRoot()
            if gap <= distance, gap < (best?.gap ?? .infinity) { best = (node, gap) }
        }
        return best?.node
    }
}

extension JourneyNode {
    /// The colour slot of the node, 0 to ``JourneyScene/paletteSize`` minus 1: 0 for a memory chunk, and for a skill
    /// a slot from 1 up that depends only on its category, so a category keeps one colour on every device.
    public var paletteIndex: Int {
        kind == .memory ? 0 : 1 + Int(JourneyHash.fnv1a(category) % UInt32(JourneyScene.paletteSize - 1))
    }
}
