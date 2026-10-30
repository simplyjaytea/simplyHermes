import HermesKit
import Testing

@Suite struct ConnectionTestRunTrackerTests {
    @Test func aRunIsCurrentOnlyWhileTheFormStillMatches() {
        var tracker = ConnectionTestRunTracker<String>()
        let run = tracker.begin("http://box:9119")
        #expect(tracker.isCurrent(run))
        #expect(tracker.isCurrent(run, target: "http://box:9119"))
        #expect(!tracker.isCurrent(run, target: "http://other:9119"))
    }

    @Test func aNewerRunSupersedesAnOlderOneWithTheSameTarget() {
        var tracker = ConnectionTestRunTracker<String>()
        let first = tracker.begin("http://box:9119")
        let second = tracker.begin("http://box:9119")
        #expect(!tracker.isCurrent(first))
        #expect(!tracker.isCurrent(first, target: "http://box:9119"))
        #expect(tracker.isCurrent(second, target: "http://box:9119"))
    }

    @Test func finishingAnOlderRunLeavesTheNewerOneCurrent() {
        var tracker = ConnectionTestRunTracker<String>()
        let first = tracker.begin("A")
        let second = tracker.begin("B")
        tracker.finish(first)
        #expect(tracker.isCurrent(second, target: "B"))
        tracker.finish(second)
        #expect(tracker.current == nil)
    }

    @Test func invalidateMakesAnEditedRunStale() {
        var tracker = ConnectionTestRunTracker<String>()
        let run = tracker.begin("A")
        tracker.invalidate()
        #expect(!tracker.isCurrent(run, target: "A"))
    }

    @Test func progressFromAFinishedRunIsStale() {
        var tracker = ConnectionTestRunTracker<String>()
        let run = tracker.begin("A")
        tracker.finish(run)
        #expect(!tracker.isCurrent(run, target: "A"))
    }
}
