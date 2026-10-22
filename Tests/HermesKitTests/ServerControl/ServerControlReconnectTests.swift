import Foundation
import HermesKit
import Testing

/// The "Reconnecting…" wait, run on a virtual clock so the 60 s window costs no real time.
@Suite struct ServerControlReconnectTests {
    @Test func stopsAtTheFirstAnswer() async throws {
        let clock = ServerControlVirtualClock()
        let script = ServerControlProbeScript([false, false, true])
        let outcome = try await ServerControlReconnect().run(clock: clock) { script.next() }
        #expect(outcome == .reachable(probes: 3))
        #expect(script.count == 3 && clock.now() == 4)
        #expect(clock.recorded == [2, 2])
    }

    @Test func givesUpAfterSixtySecondsOfProbes() async throws {
        let clock = ServerControlVirtualClock()
        let outcome = try await ServerControlReconnect().run(clock: clock) { false }
        #expect(outcome == .timedOut(probes: 31))
        #expect(clock.now() == 60)
        #expect(clock.recorded.allSatisfy { $0 == 2 })
    }

    @Test func thePlanDefaultsAreSixtySecondsAndTwoSecondProbes() {
        let defaults = ServerControlReconnect()
        #expect(defaults.window == 60 && defaults.interval == 2 && defaults.settle == 0)
    }

    @Test func theLastWaitStopsAtTheWindowEnd() async throws {
        let clock = ServerControlVirtualClock()
        let outcome = try await ServerControlReconnect(window: 5, interval: 2).run(clock: clock) { false }
        #expect(outcome == .timedOut(probes: 4))
        #expect(clock.now() == 5)
        #expect(clock.recorded == [2, 2, 1])
    }

    @Test func settleDelaysTheFirstProbe() async throws {
        let clock = ServerControlVirtualClock()
        let script = ServerControlProbeScript([true])
        let outcome = try await ServerControlReconnect(settle: 2).run(clock: clock) { script.next() }
        #expect(outcome == .reachable(probes: 1))
        #expect(clock.now() == 2)
    }

    @Test func settleCountsAgainstTheWindow() async throws {
        let clock = ServerControlVirtualClock()
        let outcome = try await ServerControlReconnect(settle: 2).run(clock: clock) { false }
        #expect(outcome == .timedOut(probes: 30))
        #expect(clock.now() == 60)
    }
}
