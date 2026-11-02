import Foundation
import Testing

@testable import HermesKit

/// Positive control for the AT-2b trap: a real transport counts its own connection. A zero for a local chat in the UI
/// test means something only if connections are seen. The WebSocket and terminal transports exist only on Apple
/// platforms, so their counters are checked by the UI test's probe on the macOS job, not here.
struct NetworkTrapTests {
    // A port nothing listens on, so the attempt fails at once and makes no real request.
    private let closed = URL(string: "http://127.0.0.1:9/")!

    @Test func anHTTPRequestIsCounted() async throws {
        let before = NetworkTrap.count(at: "http")
        _ = try? await URLSessionHTTPTransport(timeout: 2).send(HTTPRequest(method: "GET", url: closed, timeout: 2))
        #expect(NetworkTrap.count(at: "http") >= before + 1)
    }
}
