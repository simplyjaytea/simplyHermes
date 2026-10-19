import Foundation
import HermesKit
import Testing

/// The automatic layout, the viewport maths and the scene (WP-52). Everything here is pure, so the same results
/// hold on every platform.
@Suite struct JourneyLayoutTests {
    private func radius(_ point: CGPoint) -> Double {
        (Double(point.x) * Double(point.x) + Double(point.y) * Double(point.y)).squareRoot()
    }

    private func distance(_ left: CGPoint, _ right: CGPoint) -> Double {
        radius(CGPoint(x: left.x - right.x, y: left.y - right.y))
    }

    private func layout(_ graph: JourneyGraph) -> JourneyLayout {
        .radial(nodes: graph.nodes, timeline: JourneyTimeline(nodes: graph.nodes))
    }

    // MARK: Radial layout

    @Test func everyNodeGetsAPositionInsideTheDisk() {
        let graph = JourneySample.graph
        let positions = layout(graph).positions
        #expect(Set(positions.keys) == Set(graph.nodes.map(\.id)))
        for (id, point) in positions {
            #expect(radius(point) >= 0.06 - 1e-9 && radius(point) <= 0.98 + 1e-9, "\(id) at \(point)")
        }
    }

    @Test func theSameGraphAlwaysGivesTheSameLayout() {
        let graph = JourneySample.graph
        #expect(layout(graph) == layout(graph))
        let shuffled = JourneyGraph(nodes: graph.nodes.reversed(), edges: graph.edges)
        #expect(layout(shuffled) == layout(graph), "node order must not change the layout")
    }

    @Test func olderNodesSitNearerTheCentre() throws {
        let graph = JourneySample.graph
        let positions = layout(graph).positions
        let devops = graph.nodes.filter { $0.category == "devops" }.sorted { ($0.timestamp ?? 0) < ($1.timestamp ?? 0) }
        let radii = try devops.map { radius(try #require(positions[$0.id])) }
        #expect(radii == radii.sorted(), "devops radii should grow with age: \(radii)")
    }

    @Test func nodesKeepTheirDistance() {
        let positions = Array(layout(JourneySample.graph).positions)
        var closest = Double.infinity
        for (index, first) in positions.enumerated() {
            for second in positions[(index + 1)...] {
                closest = min(closest, distance(first.value, second.value))
            }
        }
        #expect(closest >= JourneyLayout.minimumGap - 1e-9, "closest pair is \(closest) apart")
    }

    @Test func aCrowdedGraphStaysInsideTheDiskAndIsStillDeterministic() {
        let crowd = (0..<300).map { JourneyNode(id: "node-\($0)", timestamp: Double($0 % 7), category: "c\($0 % 3)") }
        let graph = JourneyGraph(nodes: crowd)
        let first = layout(graph)
        #expect(first == layout(graph))
        #expect(first.positions.count == 300)
        for (id, point) in first.positions {
            #expect(radius(point) >= 0.06 - 1e-9 && radius(point) <= 0.98 + 1e-9, "\(id) at \(point)")
        }
    }

    @Test func twoNodesOnTheSameSpotAreParted() {
        // Same category and same time: the wedge arm is the only thing that keeps them apart.
        let graph = JourneyGraph(nodes: [JourneyNode(id: "a", timestamp: 5), JourneyNode(id: "b", timestamp: 5)])
        let positions = layout(graph).positions
        #expect(distance(positions["a"] ?? .zero, positions["b"] ?? .zero) >= JourneyLayout.minimumGap - 1e-9)
    }

    @Test func categoriesKeepToTheirOwnWedge() {
        let graph = JourneySample.graph
        let positions = layout(graph).positions
        func angle(_ id: String) -> Double {
            let point = positions[id] ?? .zero
            return atan2(Double(point.y), Double(point.x))
        }
        // Two skills of one category are closer in angle than a skill and a memory chunk on the far side.
        let devops = graph.nodes.filter { $0.category == "devops" }.map { angle($0.id) }
        let spread = (devops.max() ?? 0) - (devops.min() ?? 0)
        #expect(spread < Double.pi, "a wedge is narrower than half the circle: \(spread)")
    }

    @Test func emptyAndSingleGraphsAreFine() {
        #expect(layout(JourneyGraph()).positions.isEmpty)
        let single = layout(JourneyGraph(nodes: [JourneyNode(id: "only", timestamp: 5)])).positions
        #expect(single.count == 1 && radius(single["only"] ?? .zero) > 0)
    }

    // MARK: Viewport

    @Test func zoomAndCentreAreClamped() {
        #expect(JourneyViewport.clampZoom(0.01) == 0.5 && JourneyViewport.clampZoom(100) == 8)
        #expect(JourneyViewport.clampZoom(.nan) == 1 && JourneyViewport.clampZoom(2) == 2)
        let far = JourneyViewport.clampCenter(CGPoint(x: 30, y: 40))
        #expect(abs(radius(far) - JourneyViewport.reach) < 1e-9)
        #expect(JourneyViewport.clampCenter(CGPoint(x: .nan, y: 0.5)) == CGPoint(x: 0, y: 0.5))
        #expect(JourneyViewport.clampCenter(CGPoint(x: .infinity, y: -.infinity)) == .zero)
        let made = JourneyViewport(zoom: 99, center: CGPoint(x: -50, y: 0))
        #expect(made.zoom == 8 && made.center == CGPoint(x: -JourneyViewport.reach, y: 0))
        #expect(JourneyViewport.fit.zoom == 1 && JourneyViewport.fit.center == .zero)
    }

    @Test func fitPutsTheCentreInTheMiddleOfTheView() {
        let size = CGSize(width: 400, height: 600)
        let fit = JourneyViewport.fit
        #expect(fit.toView(.zero, in: size) == CGPoint(x: 200, y: 300))
        #expect(abs(fit.fitScale(in: size) - 176) < 1e-9)
        let edge = fit.toView(CGPoint(x: 1, y: 0), in: size)
        #expect(abs(Double(edge.x) - (200 + 176)) < 1e-9 && edge.y == 300)
    }

    @Test func viewAndLayoutPointsConvertBothWays() {
        let size = CGSize(width: 390, height: 700)
        let viewport = JourneyViewport(zoom: 2.5, center: CGPoint(x: 0.3, y: -0.2))
        for point in [CGPoint.zero, CGPoint(x: 0.5, y: 0.5), CGPoint(x: -0.9, y: 0.1)] {
            let back = viewport.toLayout(viewport.toView(point, in: size), in: size)
            #expect(distance(back, point) < 1e-9)
        }
    }

    @Test func pinchKeepsThePointUnderTheFingersStill() {
        let size = CGSize(width: 400, height: 600)
        let anchor = CGPoint(x: 120, y: 410)
        var viewport = JourneyViewport(zoom: 1.4, center: CGPoint(x: 0.1, y: 0.05))
        for factor in [1.3, 0.8, 1.9, 0.5] {
            let before = viewport.toLayout(anchor, in: size)
            viewport = viewport.zoomed(by: factor, around: anchor, in: size)
            let after = viewport.toLayout(anchor, in: size)
            #expect(distance(before, after) < 1e-9, "factor \(factor)")
        }
    }

    @Test func zoomStopsAtTheLimits() {
        let size = CGSize(width: 400, height: 600)
        let middle = CGPoint(x: 200, y: 300)
        var viewport = JourneyViewport.fit
        for _ in 0..<20 { viewport = viewport.zoomed(by: 2, around: middle, in: size) }
        #expect(viewport.zoom == 8)
        for _ in 0..<20 { viewport = viewport.zoomed(by: 0.5, around: middle, in: size) }
        #expect(viewport.zoom == 0.5)
    }

    @Test func badZoomFactorsChangeNothing() {
        let size = CGSize(width: 400, height: 600)
        let viewport = JourneyViewport(zoom: 2, center: CGPoint(x: 0.2, y: 0.2))
        for factor: Double in [0, -1, .nan, .infinity, -.infinity] {
            #expect(viewport.zoomed(by: factor, around: .zero, in: size) == viewport)
        }
    }

    @Test func draggingMovesTheGraphWithTheFinger() {
        let size = CGSize(width: 400, height: 600)
        let start = JourneyViewport(zoom: 2, center: .zero)
        let scale = start.scale(in: size)
        let moved = start.panned(by: CGSize(width: 50, height: -30), in: size)
        #expect(abs(Double(moved.center.x) + 50 / scale) < 1e-9 && abs(Double(moved.center.y) - 30 / scale) < 1e-9)
        let origin = start.toView(.zero, in: size)
        let after = moved.toView(.zero, in: size)
        #expect(abs(Double(after.x - origin.x) - 50) < 1e-9 && abs(Double(after.y - origin.y) + 30) < 1e-9)
    }

    @Test func panCannotLoseTheGraph() {
        let size = CGSize(width: 400, height: 600)
        let viewport = JourneyViewport.fit.panned(by: CGSize(width: -100_000, height: 100_000), in: size)
        #expect(radius(viewport.center) <= JourneyViewport.reach + 1e-9)
    }

    @Test func tweenMovesInEvenZoomSteps() {
        let start = JourneyViewport.fit
        let target = JourneyViewport(zoom: 4, center: CGPoint(x: 0.8, y: 0))
        #expect(start.interpolated(to: target, progress: 0) == start)
        #expect(start.interpolated(to: target, progress: 1) == target)
        #expect(start.interpolated(to: target, progress: .nan) == target)
        let half = start.interpolated(to: target, progress: 0.5)
        #expect(abs(half.zoom - 2) < 1e-9 && abs(Double(half.center.x) - 0.4) < 1e-9)
        #expect(start.interpolated(to: target, progress: -3) == start)
    }

    @Test func easingStartsAndEndsSoftly() {
        #expect(JourneyViewport.eased(0) == 0 && JourneyViewport.eased(1) == 1 && JourneyViewport.eased(0.5) == 0.5)
        #expect(JourneyViewport.eased(0.1) < 0.1 && JourneyViewport.eased(0.9) > 0.9, "slow at both ends")
        #expect(JourneyViewport.eased(-2) == 0 && JourneyViewport.eased(7) == 1)
        #expect(JourneyViewport.eased(.nan) == 1 && JourneyViewport.eased(.infinity) == 1)
        let steps = (0...12).map { JourneyViewport.eased(Double($0) / 12) }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 }, "never turns back")
    }

    // MARK: Scene

    private func scene(
        _ graph: JourneyGraph, filter: JourneyFilter = .all, scrub: Double = 1,
        placements: [String: CGPoint] = [:]
    ) -> JourneyScene {
        .make(
            graph: graph, layout: layout(graph), timeline: JourneyTimeline(nodes: graph.nodes),
            state: JourneyLayoutState(filter: filter, scrub: scrub, placements: placements))
    }

    @Test func sceneShowsEverythingAtTheEndOfTime() {
        let graph = journeyDatedGraph()
        let all = scene(graph)
        #expect(all.nodes.count == 5)
        #expect(all.links.count == 3, "the link to a node the graph does not hold is skipped")
        #expect(all.nodes.map(\.id) == ["old", "undated", "memory:memory:0:aa", "mid", "new"])
    }

    @Test func sceneFollowsTheFilter() {
        let graph = journeyDatedGraph()
        #expect(Set(scene(graph, filter: .used).nodes.map(\.id)) == ["old", "new"])
        #expect(Set(scene(graph, filter: .learned).nodes.map(\.id)) == ["old"])
        #expect(scene(graph, filter: .learned).links.isEmpty)
        #expect(scene(graph, filter: .used).links.isEmpty, "old and new are not linked directly")
    }

    @Test func sceneFollowsTheScrubber() {
        let graph = journeyDatedGraph()
        #expect(scene(graph, scrub: 0).nodes.map(\.id) == ["old", "undated"], "undated nodes are always there")
        #expect(Set(scene(graph, scrub: 0.3).nodes.map(\.id)) == ["undated", "old", "memory:memory:0:aa"])
        #expect(scene(graph, scrub: 0.5).nodes.count == 4)
        #expect(scene(graph, scrub: 0).links.isEmpty)
        #expect(scene(graph, scrub: 0.3).links.count == 1, "the note links to the old skill")
    }

    @Test func nodeLooksReflectWhatTheServerSays() throws {
        let sceneNodes = scene(journeyDatedGraph()).nodes
        let old = try #require(sceneNodes.first { $0.id == "old" })
        let mid = try #require(sceneNodes.first { $0.id == "mid" })
        let new = try #require(sceneNodes.first { $0.id == "new" })
        let note = try #require(sceneNodes.first { $0.kind == .memory })
        #expect(old.radius > mid.radius, "a used skill is drawn bigger")
        #expect(new.isDimmed && !old.isDimmed && old.isLearned && !mid.isLearned)
        #expect(note.label == "A note" && note.paletteIndex == 0)
        #expect(sceneNodes.allSatisfy { (0..<JourneyScene.paletteSize).contains($0.paletteIndex) })
        #expect(sceneNodes.filter { $0.kind == .skill }.allSatisfy { $0.paletteIndex > 0 }, "slot 0 is for memory")
        let beta = sceneNodes.filter { $0.id == "undated" || $0.id == "new" }
        #expect(Set(beta.map(\.paletteIndex)).count == 1, "a category keeps one colour")
    }

    @Test func archivedSkillsAreSmallerThanActiveOnesWithTheSameUse() throws {
        let graph = JourneyGraph(nodes: [
            JourneyNode(id: "live", useCount: 4), JourneyNode(id: "gone", useCount: 4, state: "archived"),
            JourneyNode(id: "kept", useCount: 4, pinned: true),
        ])
        let nodes = scene(graph).nodes
        let live = try #require(nodes.first { $0.id == "live" })
        let gone = try #require(nodes.first { $0.id == "gone" })
        let kept = try #require(nodes.first { $0.id == "kept" })
        #expect(gone.radius < live.radius && kept.radius > live.radius && kept.isPinned)
    }

    @Test func movedNodesUseTheirPlacement() throws {
        let graph = journeyDatedGraph()
        let moved = scene(graph, placements: ["mid": CGPoint(x: 0.25, y: -0.5)])
        let node = try #require(moved.nodes.first { $0.id == "mid" })
        #expect(node.position == CGPoint(x: 0.25, y: -0.5))
        let link = try #require(
            moved.links.first { $0.source == CGPoint(x: 0.25, y: -0.5) || $0.target == CGPoint(x: 0.25, y: -0.5) })
        #expect(link.source == node.position || link.target == node.position)
    }

    @Test func hitTestFindsTheClosestNodeInRange() throws {
        let nodes = scene(journeyDatedGraph()).nodes
        let target = try #require(nodes.first { $0.id == "mid" })
        let near = CGPoint(x: target.position.x + 0.001, y: target.position.y)
        #expect(scene(journeyDatedGraph()).node(near: near, within: 0.01)?.id == "mid")
        #expect(scene(journeyDatedGraph()).node(near: CGPoint(x: 5, y: 5), within: 0.5) == nil)
        #expect(JourneyScene.empty.node(near: .zero, within: 10) == nil)
    }
}
