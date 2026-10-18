import Foundation
import HermesKit
import Testing

/// The board the screen's model keeps (WP-52): filter, scrub, zoom, pan, share code and taps, all as plain values.
@Suite struct JourneyBoardTests {
    private let size = CGSize(width: 390, height: 700)

    private func fixtureBoard() throws -> JourneyBoard {
        JourneyBoard(graph: try journeyFixtureGraph())
    }

    @Test func startsWithEverythingShown() throws {
        let board = try fixtureBoard()
        #expect(!board.isEmpty && board.filter == .all && board.scrub == 1 && board.viewport == .fit)
        #expect(board.filteredCount == 9 && board.visibleCount == 9 && board.rows.count == 9)
        #expect(board.scene.links.count == 3, "the edge to a node the graph lacks is skipped")
        #expect(board.count(.used) == 5 && board.count(.learned) == 3 && board.count(.all) == 9)
        #expect(board.scrubDate == board.timeline.end)
    }

    @Test func filterChangesTheListAndTheGraphTogether() throws {
        var board = try fixtureBoard()
        board.setFilter(.used)
        #expect(board.filter == .used && board.filteredCount == 5 && board.visibleCount == 5)
        #expect(board.rows.map(\.id).first == "backup-cron-fix")
        #expect(Set(board.scene.nodes.map(\.id)) == Set(board.rows.map(\.id)))
        board.setFilter(.learned)
        #expect(board.rows.count == 3 && board.scene.links.count == 1, "cron fix links to the systemd skill")
        board.setFilter(.all)
        #expect(board.rows.count == 9 && board.visibleCount == 9)
    }

    @Test func scrubbingOnlyChangesTheGraph() throws {
        var board = try fixtureBoard()
        let rows = board.rows
        board.setScrub(0.3)
        #expect(board.rows == rows, "the list does not follow the scrubber")
        #expect(board.visibleCount < 9 && board.visibleCount > 0)
        let shown = Set(board.scene.nodes.map(\.id))
        #expect(shown.contains("legacy-notes"), "a node with no time is always there")
        #expect(!shown.contains("backup-cron-fix"))
        board.setScrub(.nan)
        #expect(board.scrub == 1 && board.visibleCount == 9)
        board.setScrub(-4)
        #expect(board.scrub == 0 && board.visibleCount >= 1)
        #expect(board.scrubDate != nil && board.scrubDate == board.timeline.start)
    }

    @Test func zoomAndPanLeaveTheSceneAlone() throws {
        var board = try fixtureBoard()
        let scene = board.scene
        board.zoom(by: 2, around: CGPoint(x: 100, y: 200), in: size)
        board.pan(by: CGSize(width: 30, height: -10), in: size)
        #expect(board.scene == scene && board.viewport.zoom == 2 && board.viewport != .fit)
        board.fit()
        #expect(board.viewport == .fit)
        board.setViewport(JourneyViewport(zoom: 99))
        #expect(board.viewport.zoom == 8)
    }

    @Test func aNewGraphKeepsTheUsersView() throws {
        var board = try fixtureBoard()
        board.setFilter(.used)
        board.setScrub(0.6)
        board.zoom(by: 3, around: .zero, in: size)
        let before = board.state
        var graph = board.graph
        graph.nodes.append(JourneyNode(id: "brand-new", timestamp: 1_790_000_000, useCount: 1))
        board.replaceGraph(graph)
        #expect(board.graph.nodes.count == 10)
        #expect(board.filter == before.filter && board.scrub == before.scrub && board.viewport == before.viewport)
        #expect(board.rows.contains { $0.id == "brand-new" })
        #expect(board.timeline.end == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func movedNodesThatWentAwayAreForgotten() throws {
        var board = try fixtureBoard()
        var placements = board.state.placements
        placements["arxiv-search"] = CGPoint(x: 0.5, y: 0.5)
        placements["gone"] = CGPoint(x: -0.5, y: -0.5)
        let code = JourneyLayoutCode.encode(JourneyLayoutState(placements: placements))
        board.apply(try JourneyLayoutCode.decode(code))
        #expect(board.state.placements.keys.sorted() == ["arxiv-search"])
        var smaller = board.graph
        smaller.nodes.removeAll { $0.id == "arxiv-search" }
        board.replaceGraph(smaller)
        #expect(board.state.placements.isEmpty)
    }

    @Test func aLayoutCodeRestoresTheView() throws {
        var sender = try fixtureBoard()
        sender.setFilter(.learned)
        sender.setScrub(0.8)
        sender.zoom(by: 2.5, around: CGPoint(x: 80, y: 120), in: size)
        sender.pan(by: CGSize(width: -40, height: 25), in: size)
        let code = sender.layoutCode
        #expect(code.hasPrefix(JourneyLayoutCode.versionPrefix))

        var receiver = try fixtureBoard()
        receiver.apply(try JourneyLayoutCode.decode(code))
        #expect(receiver.filter == .learned && receiver.rows.count == 3)
        #expect(abs(receiver.scrub - 0.8) < 1e-4)
        #expect(abs(receiver.viewport.zoom / sender.viewport.zoom - 1) < 1e-3)
        #expect(abs(Double(receiver.viewport.center.x - sender.viewport.center.x)) < 1e-4)
        #expect(abs(Double(receiver.viewport.center.y - sender.viewport.center.y)) < 1e-4)
        #expect(receiver.scene.nodes.map(\.id) == sender.scene.nodes.map(\.id))
    }

    @Test func aTapFindsTheNodeUnderTheFinger() throws {
        var board = try fixtureBoard()
        let target = try #require(board.scene.nodes.first { $0.id == "arxiv-search" })
        for zoom in [1.0, 2.0, 5.0] {
            board.setViewport(JourneyViewport(zoom: zoom, center: target.position))
            let spot = board.viewport.toView(target.position, in: size)
            #expect(board.node(at: spot, in: size, tolerance: 22)?.id == "arxiv-search", "zoom \(zoom)")
            let near = CGPoint(x: spot.x + 10, y: spot.y - 8)
            #expect(board.node(at: near, in: size, tolerance: 22)?.id == "arxiv-search")
        }
        board.fit()
        #expect(board.node(at: CGPoint(x: 2, y: 2), in: size, tolerance: 22) == nil)
        #expect(board.node(at: .zero, in: CGSize(width: 0, height: 0), tolerance: 22) == nil)
    }

    @Test func hiddenNodesCannotBeTapped() throws {
        var board = try fixtureBoard()
        let target = try #require(board.scene.nodes.first { $0.id == "backup-cron-fix" })
        let spot = board.viewport.toView(target.position, in: size)
        #expect(board.node(at: spot, in: size, tolerance: 22)?.id == "backup-cron-fix")
        board.setScrub(0)
        #expect(board.node(at: spot, in: size, tolerance: 22)?.id != "backup-cron-fix")
    }

    @Test func anEmptyBoardIsUsable() throws {
        var board = JourneyBoard.empty
        #expect(board.isEmpty && board.rows.isEmpty && board.scene.nodes.isEmpty && board.visibleCount == 0)
        #expect(board.scrubDate == nil)
        board.setFilter(.used)
        board.setScrub(0.2)
        board.zoom(by: 2, around: .zero, in: size)
        #expect(try JourneyLayoutCode.decode(board.layoutCode).filter == .used)
    }
}
