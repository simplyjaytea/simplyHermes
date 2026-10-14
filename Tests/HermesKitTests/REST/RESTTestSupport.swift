import Foundation
import HermesKit

let jsonHeaders = ["Content-Type": "application/json"]

final class FakeHTTP: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [HTTPResponse] = []
    private var seen: [HTTPRequest] = []

    func enqueue(_ status: Int, _ json: String = "{}", headers: [String: String] = jsonHeaders) {
        lock.withLock { queue.append(HTTPResponse(status: status, headers: headers, body: Data(json.utf8))) }
    }

    var requests: [HTTPRequest] { lock.withLock { seen } }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        try lock.withLock {
            seen.append(request)
            guard !queue.isEmpty else { throw RESTError.transport("no scripted response") }
            return queue.removeFirst()
        }
    }
}

/// Loads `Fixtures/rest/<name>.json`, recorded from the pinned testbed build.
func restFixture(_ name: String) throws -> String {
    let url = FixtureFiles.directory.appendingPathComponent("rest").appendingPathComponent(name + ".json")
    return try String(contentsOf: url, encoding: .utf8)
}
