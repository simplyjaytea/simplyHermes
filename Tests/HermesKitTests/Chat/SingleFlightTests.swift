import Testing

@testable import HermesKit

struct SingleFlightTests {
    @Test func aSecondStartWhileTheFirstRunsIsRefused() {
        var flight = SingleFlight()
        let first = flight.begin()
        let second = flight.begin()
        let third = flight.begin()
        #expect(first)
        #expect(!second)
        #expect(!third)
    }

    @Test func theNextStartIsAcceptedOnceTheFirstEnds() {
        var flight = SingleFlight()
        let first = flight.begin()
        flight.end()
        let next = flight.begin()
        #expect(first)
        #expect(next)
    }
}
