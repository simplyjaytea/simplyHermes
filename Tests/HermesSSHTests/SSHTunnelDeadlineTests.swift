import Foundation
import Testing

@testable import HermesSSH

/// The deadline around every SSH command in ``SSHTunnel`` (probe, launch, stop). Before it, a command whose stream
/// never ended hung `tunnel.start` until the test suite's 5-minute limit (Testbed smoke runs 41351410493 and
/// 41458357870).
struct SSHTunnelDeadlineTests {
    @Test func aCommandThatFinishesInTimeReturnsItsOutput() async throws {
        let output = try await SSHTunnel.withDeadline(
            .seconds(5), step: "probe", onTimeout: {}, body: { "HERMES_VERSION 1" })
        #expect(output == "HERMES_VERSION 1")
    }

    @Test func aCommandThatNeverEndsTimesOutAndNamesItsStep() async {
        let start = ContinuousClock.now
        await #expect(throws: SSHTunnelError.commandTimedOut(step: "launch")) {
            _ = try await SSHTunnel.withDeadline(
                .milliseconds(200), step: "launch", onTimeout: {},
                body: { () -> String in
                    try await Task.sleep(for: .seconds(60))
                    return "never"
                })
        }
        #expect(start.duration(to: .now) < .seconds(5))
    }

    /// A stream that ignores cancellation, like a stuck SSH channel, ends only when the connection closes. The deadline
    /// closes it, and the caller gets the timeout, not the stream's own "closed" error.
    @Test func theTimeoutClosesAStuckStreamAndItsErrorWins() async {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        struct ConnectionClosed: Error {}
        await #expect(throws: SSHTunnelError.commandTimedOut(step: "probe")) {
            _ = try await SSHTunnel.withDeadline(
                .milliseconds(200), step: "probe",
                onTimeout: {
                    // Like `client.close()`: the stream fails at once, but the close itself returns a little later,
                    // so the stream's own error reaches the group first.
                    continuation.finish(throwing: ConnectionClosed())
                    try? await Task.sleep(for: .milliseconds(300))
                },
                body: { () -> String in
                    var text = ""
                    for try await chunk in stream { text += chunk }
                    return text
                })
        }
    }

    @Test func anErrorBeforeTheDeadlineIsPassedOn() async {
        await #expect(throws: SSHTunnelError.hermesNotFound) {
            _ = try await SSHTunnel.withDeadline(
                .seconds(5), step: "probe", onTimeout: {},
                body: { () -> String in throw SSHTunnelError.hermesNotFound })
        }
    }

    @Test func aTimeoutReadsAsAConnectionTestFailure() {
        #expect(
            SSHConnectionTester.failure(SSHTunnelError.commandTimedOut(step: "probe"))
                == .ssh("The server didn't finish the probe step in time, so the connection was closed. Try again."))
    }
}
