import Foundation
import HermesKit
import Testing

/// The timeline behind the scrubber (WP-52): what existed at a point in time, and the fallbacks for graphs that have
/// no real time span.
@Suite struct JourneyTimelineTests {
    private func nodes(_ stamps: [(String, Double?)]) -> [JourneyNode] {
        stamps.map { JourneyNode(id: $0.0, timestamp: $0.1) }
    }

    @Test func recencyMapsTimestampsBetweenOldestAndNewest() {
        let timeline = JourneyTimeline(
            nodes: nodes([("b", 200), ("c", 300), ("a", 100), ("none", nil)]))
        #expect(timeline.hasDates)
        #expect(timeline.recency(of: "a") == 0 && timeline.recency(of: "b") == 0.5 && timeline.recency(of: "c") == 1)
        #expect(timeline.recency(of: "none") == 0)
        #expect(timeline.orderedIDs == ["none", "a", "b", "c"])
        #expect(timeline.start == Date(timeIntervalSince1970: 100) && timeline.end == Date(timeIntervalSince1970: 300))
    }

    @Test func scrubberRevealsNodesAsTimePasses() {
        let timeline = JourneyTimeline(nodes: nodes([("a", 100), ("b", 200), ("c", 300), ("none", nil)]))
        #expect(timeline.visibleIDs(at: 0) == ["none", "a"])
        #expect(timeline.visibleIDs(at: 0.49) == ["none", "a"])
        #expect(timeline.visibleIDs(at: 0.5) == ["none", "a", "b"])
        #expect(timeline.visibleIDs(at: 1) == ["none", "a", "b", "c"])
        #expect(timeline.isVisible("c", at: 1) && !timeline.isVisible("c", at: 0.99))
    }

    @Test func positionsOutsideTheScaleAreClamped() {
        let timeline = JourneyTimeline(nodes: nodes([("a", 100), ("b", 200)]))
        #expect(timeline.visibleIDs(at: -5) == ["a"])
        #expect(timeline.visibleIDs(at: 7) == ["a", "b"])
        #expect(timeline.visibleIDs(at: .nan) == ["a", "b"])
        #expect(timeline.visibleIDs(at: -.infinity) == ["a"])
        #expect(JourneyTimeline.clamp(.infinity) == 1 && JourneyTimeline.clamp(0.25) == 0.25)
    }

    @Test func positionsAndDatesConvertBothWays() throws {
        let timeline = JourneyTimeline(nodes: nodes([("a", 1_000), ("b", 3_000)]))
        #expect(timeline.date(at: 0) == Date(timeIntervalSince1970: 1_000))
        #expect(timeline.date(at: 0.5) == Date(timeIntervalSince1970: 2_000))
        #expect(timeline.date(at: 9) == Date(timeIntervalSince1970: 3_000))
        #expect(timeline.position(of: Date(timeIntervalSince1970: 2_000)) == 0.5)
        #expect(timeline.position(of: Date(timeIntervalSince1970: 0)) == 0)
        #expect(timeline.position(of: Date(timeIntervalSince1970: 99_999)) == 1)
    }

    @Test func graphsWithoutATimeSpanStepThroughTheNodesOneByOne() {
        let same = JourneyTimeline(nodes: nodes([("c", 5), ("a", 5), ("b", 5)]))
        #expect(!same.hasDates && same.start == nil && same.end == nil)
        #expect(same.orderedIDs == ["a", "b", "c"])
        #expect(same.recency(of: "a") == 0 && same.recency(of: "b") == 0.5 && same.recency(of: "c") == 1)
        #expect(same.date(at: 0.5) == nil && same.position(of: Date()) == nil)
        #expect(same.visibleIDs(at: 0.5) == ["a", "b"])

        let undated = JourneyTimeline(nodes: nodes([("z", nil), ("y", nil)]))
        #expect(!undated.hasDates && undated.orderedIDs == ["y", "z"])
        #expect(undated.visibleIDs(at: 0) == ["y"] && undated.visibleIDs(at: 1) == ["y", "z"])
    }

    @Test func oneNodeAndNoNodesAreHandled() {
        let single = JourneyTimeline(nodes: nodes([("only", 10)]))
        #expect(single.recency(of: "only") == 0 && single.visibleIDs(at: 0) == ["only"])
        let empty = JourneyTimeline(nodes: [])
        #expect(empty.orderedIDs.isEmpty && empty.visibleIDs(at: 1).isEmpty && !empty.hasDates)
    }

    @Test func unknownNodesCountAsNewest() {
        let timeline = JourneyTimeline(nodes: nodes([("a", 1), ("b", 2)]))
        #expect(timeline.recency(of: "ghost") == 1)
        #expect(!timeline.isVisible("ghost", at: 0.5) && timeline.isVisible("ghost", at: 1))
    }

    @Test func orderDoesNotDependOnInputOrder() {
        let list = nodes([("a", 1), ("b", 2), ("c", 3), ("d", nil), ("e", 2)])
        #expect(JourneyTimeline(nodes: list) == JourneyTimeline(nodes: list.reversed()))
        #expect(JourneyTimeline(nodes: list).orderedIDs == ["d", "a", "b", "e", "c"])
    }
}
