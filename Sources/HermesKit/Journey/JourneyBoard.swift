import Foundation

/// A loaded graph and everything the memory screen draws from it: the timeline, the automatic layout, the filter,
/// the scrub position, zoom and pan, the nodes on screen and the rows of the list.
///
/// The screen's model keeps one of these and forwards every gesture and tap to it. All the rules live here as plain
/// value changes, so they run in tests on Linux. Layout and timeline are computed once per graph; a filter or scrub
/// change only rebuilds the scene, and zoom and pan rebuild nothing.
public struct JourneyBoard: Sendable, Equatable {
    /// The graph as the server sent it.
    public private(set) var graph: JourneyGraph
    /// Filter, scrub, zoom, pan and moved nodes.
    public private(set) var state: JourneyLayoutState
    /// When each node came to be.
    public private(set) var timeline: JourneyTimeline
    /// The automatic positions.
    public private(set) var layout: JourneyLayout
    /// The nodes and links on screen.
    public private(set) var scene: JourneyScene
    /// The nodes that pass the filter, newest first, for the list.
    public private(set) var rows: [JourneyNode]

    /// A board with nothing in it.
    public static let empty = JourneyBoard()

    /// Creates a board for `graph`. `state` carries a filter, zoom or scrub position to start from.
    public init(graph: JourneyGraph = JourneyGraph(), state: JourneyLayoutState = JourneyLayoutState()) {
        let timeline = JourneyTimeline(nodes: graph.nodes)
        self.graph = graph
        self.state = state
        self.timeline = timeline
        layout = .radial(nodes: graph.nodes, timeline: timeline)
        scene = .empty
        rows = []
        rebuildScene()
        rebuildRows()
    }

    // MARK: - Reading

    /// The chosen filter.
    public var filter: JourneyFilter { state.filter }

    /// The scrub position, 0 to 1.
    public var scrub: Double { state.scrub }

    /// Zoom and pan.
    public var viewport: JourneyViewport { state.viewport }

    /// True when the graph has no nodes.
    public var isEmpty: Bool { graph.nodes.isEmpty }

    /// How many nodes pass the chosen filter.
    public var filteredCount: Int { rows.count }

    /// How many nodes are on screen: they pass the filter and already existed at the scrub position.
    public var visibleCount: Int { scene.nodes.count }

    /// The moment the scrub position stands for. Nil when the graph has no time span.
    public var scrubDate: Date? { timeline.date(at: state.scrub) }

    /// The code that restores this view on another device.
    public var layoutCode: String { JourneyLayoutCode.encode(state) }

    /// How many nodes `filter` would show, for the chip counts.
    public func count(_ filter: JourneyFilter) -> Int { graph.count(filter) }

    /// The node under a touch at `point` in a view of `size`, if one lies within `tolerance` points of it.
    public func node(at point: CGPoint, in size: CGSize, tolerance: Double) -> JourneyScene.Node? {
        guard size.width > 0, size.height > 0, tolerance > 0 else { return nil }
        let scale = state.viewport.scale(in: size)
        return scene.node(near: state.viewport.toLayout(point, in: size), within: tolerance / scale)
    }

    // MARK: - Changing

    /// Swaps in a fresh graph and keeps the user's filter, scrub position, zoom and pan. Moved nodes that the new
    /// graph no longer holds are forgotten.
    public mutating func replaceGraph(_ newGraph: JourneyGraph) {
        graph = newGraph
        timeline = JourneyTimeline(nodes: newGraph.nodes)
        layout = .radial(nodes: newGraph.nodes, timeline: timeline)
        let known = Set(newGraph.nodes.map(\.id))
        state.placements = state.placements.filter { known.contains($0.key) }
        rebuildScene()
        rebuildRows()
    }

    /// Chooses a filter.
    public mutating func setFilter(_ filter: JourneyFilter) {
        guard filter != state.filter else { return }
        state.filter = filter
        rebuildScene()
        rebuildRows()
    }

    /// Moves the scrubber. The position is kept inside 0 to 1.
    public mutating func setScrub(_ position: Double) {
        let clamped = JourneyTimeline.clamp(position)
        guard clamped != state.scrub else { return }
        state.scrub = clamped
        rebuildScene()
    }

    /// Sets zoom and pan.
    public mutating func setViewport(_ viewport: JourneyViewport) {
        state.viewport = viewport
    }

    /// Shows the whole graph again.
    public mutating func fit() {
        state.viewport = .fit
    }

    /// Zooms by `factor` and keeps the point under `anchor` where it is, like a pinch.
    public mutating func zoom(by factor: Double, around anchor: CGPoint, in size: CGSize) {
        state.viewport = state.viewport.zoomed(by: factor, around: anchor, in: size)
    }

    /// Moves the view by a drag of `translation` points.
    public mutating func pan(by translation: CGSize, in size: CGSize) {
        state.viewport = state.viewport.panned(by: translation, in: size)
    }

    /// Takes over a layout code's filter, scrub position, zoom, pan and moved nodes.
    public mutating func apply(_ code: JourneyLayoutCode.Decoded) {
        state = code.state(for: graph)
        rebuildScene()
        rebuildRows()
    }

    private mutating func rebuildScene() {
        scene = .make(graph: graph, layout: layout, timeline: timeline, state: state)
    }

    private mutating func rebuildRows() {
        rows = graph.listed(state.filter)
    }
}
