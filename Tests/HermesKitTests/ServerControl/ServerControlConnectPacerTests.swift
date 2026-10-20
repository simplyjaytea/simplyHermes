import Foundation
import HermesKit
import Testing

@Suite struct ServerControlConnectPacerTests {
    @Test func theFirstConnectIsAllowed() async {
        let pacer = ServerControlConnectPacer()
        #expect(await pacer.mayConnect(at: ContinuousClock.now))
    }

    @Test func connectsAreSpacedOut() async {
        let pacer = ServerControlConnectPacer(spacing: .seconds(15))
        let start = ContinuousClock.now
        #expect(await pacer.mayConnect(at: start))
        #expect(await pacer.mayConnect(at: start + .seconds(14)) == false)
        #expect(await pacer.mayConnect(at: start + .seconds(15)))
        #expect(await pacer.mayConnect(at: start + .seconds(29)) == false)
    }

    @Test func theBudgetCapsTheConnects() async {
        let pacer = ServerControlConnectPacer(spacing: .seconds(15), budget: 2)
        let start = ContinuousClock.now
        #expect(await pacer.mayConnect(at: start))
        #expect(await pacer.mayConnect(at: start + .seconds(15)))
        #expect(await pacer.mayConnect(at: start + .seconds(600)) == false)
    }

    @Test func theDefaultSpacingIsFifteenSeconds() {
        #expect(ServerControlConnectPacer.defaultSpacing == .seconds(15))
    }
}
