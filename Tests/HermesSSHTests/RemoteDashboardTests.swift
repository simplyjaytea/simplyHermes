import Foundation
import Testing

@testable import HermesSSH

@Suite struct RemoteDashboardTests {
    @Test func identifiersHaveServerFormats() {
        #expect(RemoteDashboard.isLowerHex(RemoteDashboard.makeOwnershipID(), count: 32))
        #expect(RemoteDashboard.isLowerHex(RemoteDashboard.makeNonce(), count: 16))
        #expect(RemoteDashboard.isLowerHex(RemoteDashboard.makeSessionToken(), count: 64))
        #expect(RemoteDashboard.makeSessionToken() != RemoteDashboard.makeSessionToken())
    }

    @Test func scriptsAreSingleQuotedForAnyLoginShell() throws {
        let probe = try RemoteDashboard.probeCommand(customPath: nil)
        #expect(probe.hasPrefix("sh -c '") && probe.hasSuffix("'"))
        #expect(probe.dropFirst(7).dropLast().contains("'") == false)

        let launch = try RemoteDashboard.launchCommand(
            hermesPath: "/usr/local/bin/hermes", ownershipID: String(repeating: "a", count: 32),
            nonce: String(repeating: "b", count: 16), token: String(repeating: "c", count: 64),
            readyTimeout: .seconds(45))
        #expect(launch.hasPrefix("sh -c '"))
        #expect(launch.contains("serve --isolated --host 127.0.0.1 --port 0"))
        #expect(launch.contains("--ssh-session-token-file \"$T\" --ssh-owner-nonce bbbbbbbbbbbbbbbb"))
        #expect(launch.contains("HERMES_DESKTOP=1"))
        #expect(launch.contains("-lt 90 "))
        // Reaps only servers whose token file lives in this connection's ownership dir.
        #expect(launch.contains("grep -- \"--ssh-session-token-file $D/\""))
    }

    @Test func customPathIsUsedAloneAndValidated() throws {
        let probe = try RemoteDashboard.probeCommand(customPath: "~/venv/bin/hermes")
        #expect(probe.contains("H=\"$HOME/venv/bin/hermes\""))
        #expect(!probe.contains("command -v hermes"))
        #expect(throws: SSHTunnelError.self) { try RemoteDashboard.probeCommand(customPath: "hermes; rm -rf ~") }
        #expect(throws: SSHTunnelError.self) { try RemoteDashboard.probeCommand(customPath: "/a'b") }
        #expect(throws: SSHTunnelError.self) { try RemoteDashboard.probeCommand(customPath: "relative/hermes") }
    }

    @Test func launchRejectsMalformedValues() {
        #expect(throws: SSHTunnelError.self) {
            try RemoteDashboard.launchCommand(
                hermesPath: "/bin/hermes", ownershipID: "XYZ", nonce: RemoteDashboard.makeNonce(),
                token: RemoteDashboard.makeSessionToken(), readyTimeout: .seconds(5))
        }
        #expect(throws: SSHTunnelError.self) {
            try RemoteDashboard.launchCommand(
                hermesPath: "~/hermes", ownershipID: RemoteDashboard.makeOwnershipID(),
                nonce: RemoteDashboard.makeNonce(), token: RemoteDashboard.makeSessionToken(),
                readyTimeout: .seconds(5))
        }
    }

    @Test func parsesProbe() throws {
        let probe = try RemoteDashboard.parseProbe(
            "HERMES_PATH=/usr/local/bin/hermes\nHERMES_VERSION=Hermes Agent vunknown (2026.9.24) · stable\n"
                + "HERMES_SSH_TOKEN_FILE=1\n")
        #expect(probe.hermesPath == "/usr/local/bin/hermes")
        #expect(probe.version.contains("2026.9.24"))
        #expect(probe.supportsTokenFile)
        #expect(throws: SSHTunnelError.hermesNotFound) { try RemoteDashboard.parseProbe("HERMES_NOT_FOUND\n") }
        #expect(throws: SSHTunnelError.self) { try RemoteDashboard.parseProbe("garbage") }
    }

    @Test func parsesLaunchOutcomes() throws {
        let output = "HERMES_PID=4242\nHERMES_BACKEND_READY port=41235\n"
        #expect(RemoteDashboard.parsePID(output) == 4242)
        #expect(try RemoteDashboard.parseReady(output) == 41235)
        #expect(throws: SSHTunnelError.dashboardExited(log: "Traceback: boom")) {
            try RemoteDashboard.parseReady("HERMES_PID=1\nHERMES_EXITED\nTraceback: boom\n")
        }
        #expect(throws: SSHTunnelError.dashboardStartTimedOut) {
            try RemoteDashboard.parseReady("HERMES_PID=1\nHERMES_TIMEOUT\n")
        }
    }

    @Test func stopOnlyKillsOurProcess() throws {
        let command = try RemoteDashboard.stopCommand(
            ownershipID: String(repeating: "a", count: 32), nonce: "0123456789abcdef", pid: 77)
        #expect(command.contains("ps -o args= -p 77"))
        #expect(command.contains("--ssh-owner-nonce 0123456789abcdef"))
        #expect(!command.contains("--stop"))
        #expect(throws: SSHTunnelError.self) {
            try RemoteDashboard.stopCommand(ownershipID: String(repeating: "a", count: 32), nonce: "x", pid: 1)
        }
    }

    @Test func adoptsServedToken() {
        let html = #"<script>window.__HERMES_SESSION_TOKEN__="abc123";</script>"#
        #expect(RemoteDashboard.parseServedToken(html: html) == "abc123")
        #expect(RemoteDashboard.parseServedToken(html: "<html></html>") == nil)
    }
}
