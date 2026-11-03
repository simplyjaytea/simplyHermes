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
        let closed = Flag()
        await #expect(throws: SSHTunnelError.commandTimedOut(step: "probe")) {
            _ = try await SSHTunnel.withDeadline(
                .milliseconds(200), step: "probe",
                onTimeout: {
                    closed.set()
                    continuation.finish(throwing: ConnectionClosed())
                },
                body: { () -> String in
                    var text = ""
                    for try await chunk in stream { text += chunk }
                    return text
                })
        }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(closed.isSet, "The timeout closes the connection")
    }

    /// Dinesh's M1 on #118: a close that hangs must not hold the caller. The deadline answers at 200 ms even though the
    /// close takes 60 s.
    @Test func aHangingCloseDoesNotHoldTheCaller() async {
        let start = ContinuousClock.now
        await #expect(throws: SSHTunnelError.commandTimedOut(step: "launch")) {
            _ = try await SSHTunnel.withDeadline(
                .milliseconds(200), step: "launch",
                onTimeout: { try? await Task.sleep(for: .seconds(60)) },
                body: { () -> String in
                    try await Task.sleep(for: .seconds(60))
                    return "never"
                })
        }
        #expect(start.duration(to: .now) < .seconds(5))
    }

    /// Dinesh's m1 on #118: a command that finishes before the deadline keeps its connection.
    @Test func aCommandThatFinishesFirstNeverClosesTheConnection() async throws {
        let closed = Flag()
        let output = try await SSHTunnel.withDeadline(
            .milliseconds(100), step: "probe", onTimeout: { closed.set() }, body: { "done" })
        #expect(output == "done")
        try await Task.sleep(for: .milliseconds(300))
        #expect(!closed.isSet, "A finished command must not close the connection when its deadline passes")
    }

    @Test func aCancelledCallerIsAnsweredAtOnce() async {
        let start = ContinuousClock.now
        let call = Task {
            try await SSHTunnel.withDeadline(
                .seconds(60), step: "probe", onTimeout: {},
                body: { () -> String in
                    try await Task.sleep(for: .seconds(60))
                    return "never"
                })
        }
        try? await Task.sleep(for: .milliseconds(100))
        call.cancel()
        await #expect(throws: CancellationError.self) { _ = try await call.value }
        #expect(start.duration(to: .now) < .seconds(5))
    }

    @Test func anErrorBeforeTheDeadlineIsPassedOn() async {
        await #expect(throws: SSHTunnelError.hermesNotFound) {
            _ = try await SSHTunnel.withDeadline(
                .seconds(5), step: "probe", onTimeout: {},
                body: { () -> String in throw SSHTunnelError.hermesNotFound })
        }
    }

    /// Poppy's copy on #118: plain words per step, never the internal step name.
    @Test(arguments: [
        ("probe", "The server stopped responding while looking for Hermes. Try again."),
        ("launch", "The server stopped responding while starting Hermes. Try again."),
        ("stop", "The server stopped responding. Try again."),
    ])
    func aTimeoutReadsAsPlainWords(step: String, message: String) {
        #expect(SSHConnectionTester.failure(SSHTunnelError.commandTimedOut(step: step)) == .ssh(message))
    }

    @Test func theStepNameStaysInTheErrorForLogs() {
        #expect(String(reflecting: SSHTunnelError.commandTimedOut(step: "launch")).contains("launch"))
    }
}

/// Set once, read from any task.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool { lock.withLock { value } }

    func set() { lock.withLock { value = true } }
}
