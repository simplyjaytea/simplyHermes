import Foundation
import Testing

@testable import HermesKit

struct PlaceholderStripTests {
    private func strip(_ phase: ConnectionPhase?, path: NetworkPath = .satisfied) -> PlaceholderStrip {
        PlaceholderStrip.derive(serverName: "Office Mac", phase: phase, path: path)
    }

    @Test func showsTheSavedServersNameNotAPlaceholderName() {
        #expect(strip(.connected(ServerSummary())).serverName == "Office Mac")
        #expect(strip(.connected(ServerSummary())).serverName != "home-server")
    }

    @Test func aConnectedServerReadsOnline() {
        #expect(strip(.connected(ServerSummary())).connection == .online)
    }

    @Test func aServerThatIsNotConnectedYetDoesNotReadOnline() {
        #expect(strip(nil).connection == .reconnecting)
        #expect(strip(.idle).connection == .reconnecting)
        #expect(strip(.connecting).connection == .reconnecting)
        #expect(strip(.reconnecting(attempt: 1)).connection == .reconnecting)
    }

    @Test func noNetworkReadsOfflineEvenIfTheLastPhaseWasConnected() {
        #expect(strip(.connected(ServerSummary()), path: .unsatisfied).connection == .offline)
    }

    @Test func aServerNeedingSignInReadsNeedsAttention() {
        #expect(strip(.signInRequired).connection == .needsAttention)
    }

    @Test func noServerSavedSaysSoAndReadsOffline() {
        #expect(PlaceholderStrip.noServer.serverName == "No server")
        #expect(PlaceholderStrip.noServer.connection == .offline)
    }
}
