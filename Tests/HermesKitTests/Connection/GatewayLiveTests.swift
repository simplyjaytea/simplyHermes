import Foundation
import HermesKit
import Testing

/// Runs against the WP-03 testbed when `HERMES_TESTBED_URL` is set. Without it the test passes without doing anything.
/// Drives the real `GatewayClient` over a real `/api/ws`: handshake, session create, one scripted chat turn.
@Suite struct GatewayLiveTests {
    @Test func chatTurnThroughTheRealGateway() async throws {
        guard let base = ProcessInfo.processInfo.environment["HERMES_TESTBED_URL"],
            let endpoint = HermesEndpoint(string: base)
        else { return }
        let rest = RESTClient(endpoint: endpoint, transport: URLSessionHTTPTransport())
        try await rest.passwordLogin(username: "tester", password: "testbed-password")
        let client = GatewayClient(
            endpoint: endpoint, transport: NIOWebSocketTransport(),
            credentials: await rest.gatewayCredentialProvider(login: nil))
        let events = await client.events()
        await client.start()

        let reply = try await withTimeout(seconds: 60) { () -> String? in
            for await event in events {
                switch event {
                case .state(.connected):
                    let session = try await client.call(
                        "session.create", params: SessionCreateParams(), as: SessionCreateResult.self)
                    let submit = try await client.call(
                        "prompt.submit",
                        params: PromptSubmitParams(sessionID: session.sessionID, text: "hello [[scenario:text]]"),
                        as: PromptSubmitResult.self)
                    #expect(submit.status != nil)
                case .event(let envelope, _):
                    if case .messageComplete(let done) = envelope.event { return done.text }
                default: continue
                }
            }
            return nil
        }
        await client.stop()
        #expect(reply?.isEmpty == false)
    }
}

private func withTimeout<T: Sendable>(
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
