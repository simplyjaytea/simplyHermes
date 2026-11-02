import Foundation
import HermesKit
import Testing

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set. Without it the test passes without doing anything.
/// Opens a real `/api/pty` with the testbed's sign-in, sends the window size, and waits for the PTY to write something.
@Suite struct TerminalLiveTests {
    // Quarantined (board row quarantine-terminal-live-pty, until 2026-11-09): the testbed PTY wrote nothing within 60 s in
    // Testbed smoke runs 39224003870, 41282852345 and 41394939027 (CancellationError from withTerminalTimeout). Not a
    // user-rule guard. Re-enable with the fix.
    @Test(.disabled("Quarantined: testbed PTY sometimes writes nothing within 60 s (row quarantine-terminal-live-pty)"))
    func ptyWritesOutputAfterTheWindowSizeArrives() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let rest = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())
        try await rest.passwordLogin(username: "tester", password: "testbed-password")
        let connector = TerminalConnector(
            endpoint: endpoint,
            credentials: await rest.gatewayCredentialProvider(login: nil),
            transport: NIOTerminalSocketTransport())

        let connection = try await connector.open(
            attach: "live-\(UUID().uuidString.lowercased())", profile: nil, columns: 100, rows: 30)
        let output = try await withTerminalTimeout(seconds: 60) { () -> Data? in
            for try await bytes in connection.output where !bytes.isEmpty {
                return bytes
            }
            return nil
        }
        await connection.close()
        #expect(output != nil)
    }
}

private func withTerminalTimeout<T: Sendable>(
    seconds: Double, _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw CancellationError()
        }
        defer { group.cancelAll() }
        return try await group.next()!
    }
}
