import Foundation
import HermesKit
import Testing

/// The fleet update: one server at a time, in saved order, and a failure on one server does not stop the rest.
@Suite struct FleetUpdateRunnerTests {
    private func servers(_ names: [String]) -> [ServerConnection] {
        names.map { name in
            ServerConnection(
                name: name, kind: .gateway(GatewaySettings(endpoint: HermesEndpoint(string: "http://\(name):9119")!)))
        }
    }

    @Test func everyServerRunsInSavedOrder() async {
        let log = ServerControlCallLog()
        let entries = await FleetUpdateRunner.run(servers(["home", "studio", "lab"])) { server in
            log.record(server.name)
            return .upToDate
        }
        #expect(log.names == ["home", "studio", "lab"])
        #expect(entries.map(\.server.name) == ["home", "studio", "lab"])
        #expect(entries.allSatisfy { $0.state == .done(.upToDate) })
    }

    @Test func aFailureIsRecordedAndTheNextServerStillRuns() async {
        let log = ServerControlCallLog()
        let entries = await FleetUpdateRunner.run(servers(["home", "studio", "lab"])) { server in
            log.record(server.name)
            if server.name == "studio" { throw ServerControlError.notConnected }
            return .checkUnclear(message: nil)
        }
        #expect(log.names == ["home", "studio", "lab"])
        #expect(
            entries.map(\.state) == [
                .done(.checkUnclear(message: nil)),
                .failed("Couldn't reach this server. Check that it is connected."),
                .done(.checkUnclear(message: nil)),
            ])
    }

    @Test func cancellingStopsAfterTheCurrentServer() async {
        let entries = await FleetUpdateRunner.run(servers(["home", "studio", "lab"])) { server in
            if server.name == "home" {
                withUnsafeCurrentTask { $0?.cancel() }
            }
            return .upToDate
        }
        #expect(entries.map(\.state) == [.done(.upToDate), .stopped, .stopped])
    }

    @Test func noServersMeansNoEntries() async {
        let entries = await FleetUpdateRunner.run([]) { _ in .upToDate }
        #expect(entries.isEmpty)
    }
}
