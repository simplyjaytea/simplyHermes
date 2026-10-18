import Foundation
import HermesKit
import Testing

/// Each test decodes an inline answer through the REST client, so the snake_case strategy is the real one.
@Suite struct ServerControlDecodingTests {
    private func answer<T: Sendable>(_ json: String, _ call: (RESTClient) async throws -> T) async throws -> T {
        let http = FakeHTTP()
        http.enqueue(200, json)
        return try await call(makeClient(http))
    }

    private static let statusJSON = #"""
        {
          "active_agents": 0, "active_sessions": 0, "auth_flows": ["cookie", "native_pkce"],
          "auth_providers": ["basic"], "auth_required": true, "can_update_hermes": true,
          "components": {"gateway": {"state": "stopped", "status": "degraded"}},
          "config_version": 0, "gateway_busy": false, "gateway_drainable": false,
          "gateway_exit_reason": null, "gateway_mode": "none", "gateway_running": false,
          "gateway_state": null, "latest_config_version": 50, "overall": "degraded",
          "profiles": ["default", "ops"], "release_date": "2026.9.24", "restart_drain_timeout": 0.0,
          "version": "unknown", "a_field_from_a_newer_server": {"nested": [1, 2]}
        }
        """#

    @Test func statusReadsCompatibilityAndGatewayFields() async throws {
        let status = try await answer(Self.statusJSON) { try await $0.controlStatus() }
        #expect(status.server.releaseDate == "2026.9.24" && status.server.latestConfigVersion == 50)
        #expect(status.server.gatewayRunning == false && status.server.overall == "degraded")
        #expect(status.gateway.gatewayState == nil && status.gateway.gatewayMode == "none")
        #expect(status.gateway.gatewayBusy == false && status.gateway.gatewayDrainable == false)
        #expect(status.gateway.gatewayExitReason == nil && status.gateway.canUpdateHermes == true)
        #expect(ServerCompatibility.check(status.server) == .compatible)
    }

    @Test func statusFieldsOfAnUnexpectedTypeAreNilNotFatal() async throws {
        let json =
            #"{"release_date": "2026.9.24", "gateway_state": {"x": 1}, "gateway_busy": "maybe", "gateway_mode": "multiplex"}"#
        let status = try await answer(json) { try await $0.controlStatus() }
        #expect(status.gateway.gatewayState == nil && status.gateway.gatewayBusy == nil)
        #expect(status.gateway.gatewayMode == "multiplex" && status.server.releaseDate == "2026.9.24")
    }

    @Test func oldReleaseIsTooOld() async throws {
        let status = try await answer(#"{"release_date": "2026.9.1", "latest_config_version": 50}"#) {
            try await $0.controlStatus()
        }
        #expect(ServerCompatibility.check(status.server) == .updateRequired(found: "release 2026.9.1"))
    }

    @Test func updateCheckReadsTheDocumentedFields() async throws {
        let json = #"""
            {
              "install_method": "git", "current_version": "0.19.0", "behind": 3,
              "update_available": true, "can_apply": true, "update_command": "hermes update", "message": null,
              "commits": [{"sha": "abc1234", "summary": "Fix logs", "author": "dev", "at": "2026-10-17T10:00:00Z", "extra": 1}],
              "a_future_key": "ignored"
            }
            """#
        let check = try await answer(json) { try await $0.hermesUpdateCheck(force: false) }
        #expect(check.installMethod == "git" && check.currentVersion == "0.19.0" && check.behind == 3)
        #expect(check.updateAvailable == true && check.canApply == true && check.updateCommand == "hermes update")
        #expect(check.message == nil)
        let commit = HermesUpdateCommit(sha: "abc1234", summary: "Fix logs", author: "dev", at: "2026-10-17T10:00:00Z")
        #expect(check.commits == [commit])
    }

    @Test func updateCheckToleratesUnknownCountsAndOddTypes() async throws {
        let json = #"{"behind": -1, "update_available": null, "commits": [{"sha": "x", "at": 1760000000}]}"#
        let check = try await answer(json) { try await $0.hermesUpdateCheck(force: true) }
        #expect(check.behind == -1 && check.updateAvailable == nil && check.canApply == nil)
        #expect(check.commits?.first?.sha == "x" && check.commits?.first?.at == nil)
    }

    @Test func receiptIsKeptAsJSON() async throws {
        let json = #"{"ok": true, "steps": [{"name": "pull", "ok": true}], "summary": {"status": "ok"}}"#
        let receipt = try await answer(json) { try await $0.hermesUpdateReceipt() }
        let expected: JSONValue = .object([
            "ok": .bool(true),
            "steps": .array([.object(["name": .string("pull"), "ok": .bool(true)])]),
            "summary": .object(["status": .string("ok")]),
        ])
        #expect(receipt == expected)
    }

    @Test func receiptNotFoundMeansNoReceiptYet() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"no receipt"}"#)
        let receipt = try await makeClient(http).hermesUpdateReceipt()
        #expect(receipt == nil)
    }

    @Test func untypedAnswersKeepTheirKeys() async throws {
        let stats = try await answer(#"{"cpu_percent": 12.5, "memory": {"total_mb": 4096}}"#) {
            try await $0.systemStats()
        }
        #expect(stats == .object(["cpu_percent": .double(12.5), "memory": .object(["total_mb": .int(4096)])]))
    }
}
