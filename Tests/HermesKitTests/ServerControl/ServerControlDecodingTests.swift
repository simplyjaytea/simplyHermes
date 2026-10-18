import Foundation
import HermesKit
import Testing

/// Each test decodes an inline answer through the REST client, so the snake_case strategy is the real one. The inline
/// answers are copies of one recorder run's bodies in Fixtures/rest at e3dc403, trimmed. Values change between runs,
/// so the tests check the keys and types the app reads.
@Suite struct ServerControlDecodingTests {
    private func answer<T: Sendable>(_ json: String, _ call: (RESTClient) async throws -> T) async throws -> T {
        let http = FakeHTTP()
        http.enqueue(200, json)
        return try await call(makeClient(http))
    }

    /// A copy of GET_api_status.json's body (one run, trimmed), plus one key the app does not know, so that extra keys
    /// are checked to be ignored.
    private static let statusJSON = #"""
        {
          "active_agents": 0, "active_sessions": 1, "auth_flows": ["cookie", "native_pkce"],
          "auth_providers": ["basic"], "auth_required": true, "can_update_hermes": true,
          "components": {"gateway": {"state": "stopped", "status": "degraded"}},
          "config_version": 0, "gateway_busy": false, "gateway_drainable": false,
          "gateway_exit_reason": null, "gateway_mode": "none", "gateway_running": false,
          "gateway_state": null, "latest_config_version": 50, "overall": "degraded",
          "profiles": ["default"], "release_date": "2026.9.24", "restart_drain_timeout": 0.0,
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

    @Test func gatewayFieldsOfAnUnexpectedTypeAreNilNotFatal() async throws {
        let json = #"""
            {"release_date": "2026.9.24", "gateway_state": {"x": 1}, "gateway_busy": "maybe",
             "gateway_mode": "multiplex"}
            """#
        let status = try await answer(json) { try await $0.controlStatus() }
        #expect(status.gateway.gatewayState == nil && status.gateway.gatewayBusy == nil)
        #expect(status.gateway.gatewayMode == "multiplex" && status.server.releaseDate == "2026.9.24")
    }

    /// `gateway_state` and `gateway_exit_reason` are null in the recording, so their text type is unconfirmed. Text
    /// reads as text. Any other type reads as nil and never fails the status.
    @Test func gatewayTextFieldsReadTextAndIgnoreOtherTypes() async throws {
        let text = try await answer(#"{"gateway_state": "running", "gateway_exit_reason": "crashed"}"#) {
            try await $0.controlStatus()
        }
        #expect(text.gateway.gatewayState == "running" && text.gateway.gatewayExitReason == "crashed")
        let other = try await answer(#"{"gateway_state": 7, "gateway_exit_reason": ["x"], "gateway_mode": "none"}"#) {
            try await $0.controlStatus()
        }
        #expect(other.gateway.gatewayState == nil && other.gateway.gatewayExitReason == nil)
        #expect(other.gateway.gatewayMode == "none")
    }

    @Test func oldReleaseIsTooOld() async throws {
        let status = try await answer(#"{"release_date": "2026.9.1", "latest_config_version": 50}"#) {
            try await $0.controlStatus()
        }
        #expect(ServerCompatibility.check(status.server) == .updateRequired(found: "release 2026.9.1"))
    }

    /// A copy of GET_api_hermes_update_check.json's committed body (run 1). Its `commits` list is empty here, so its
    /// entries are not read.
    private static let updateCheckJSON = #"""
        {
          "behind": -1, "can_apply": true, "commits": [], "current_version": "git.d97007c",
          "install_method": "git", "message": null, "update_available": true, "update_command": "hermes update"
        }
        """#

    @Test func updateCheckReadsTheRecordedFields() async throws {
        let check = try await answer(Self.updateCheckJSON) { try await $0.hermesUpdateCheck(force: false) }
        #expect(check.installMethod == "git" && check.currentVersion == "git.d97007c" && check.behind == -1)
        #expect(check.updateAvailable == true && check.canApply == true && check.updateCommand == "hermes update")
        #expect(check.message == nil)
    }

    @Test func updateCheckToleratesNullsAndOddTypes() async throws {
        let json = #"{"behind": "unknown", "update_available": null, "can_apply": "yes", "commits": "none"}"#
        let check = try await answer(json) { try await $0.hermesUpdateCheck(force: true) }
        #expect(check.behind == nil && check.updateAvailable == nil && check.canApply == nil && check.commits == nil)
    }

    /// The error answer of GET_api_hermes_update_check.json, as Fixtures/rest/README.md gives its body (status 200). It
    /// has no `commits` key, `behind` is null, `update_available` is false, and `message` is the error text.
    @Test func updateCheckErrorAnswerIsNotReadAsUpToDate() async throws {
        let json = #"""
            {
              "behind": null, "can_apply": true, "current_version": "git.d97007c", "install_method": "git",
              "message": "Couldn't reach the update source — try again later.", "update_available": false,
              "update_command": "hermes update"
            }
            """#
        let check = try await answer(json) { try await $0.hermesUpdateCheck(force: true) }
        #expect(check.installMethod == "git" && check.currentVersion == "git.d97007c" && check.canApply == true)
        #expect(check.updateCommand == "hermes update" && check.updateAvailable == false && check.behind == nil)
        #expect(check.commits == nil)
        #expect(check.message == "Couldn't reach the update source — try again later.")
        #expect(check.isUpToDate == false)
    }

    /// A `commits` list is kept as JSON. The keys of its entries are not recorded, so none are read.
    @Test func updateCheckCommitsStayAsJSON() async throws {
        let check = try await answer(#"{"update_available": true, "commits": [{}, {}]}"#) {
            try await $0.hermesUpdateCheck(force: false)
        }
        #expect(check.commits?.count == 2)
    }

    @Test func receiptIsKeptAsJSON() async throws {
        let receipt = try await answer(#"{"status": "ok"}"#) { try await $0.hermesUpdateReceipt() }
        let expected: JSONValue = .object(["status": .string("ok")])
        #expect(receipt == expected)
    }

    /// The body of GET_api_hermes_update_receipt.json, the only receipt answer the testbed recorded (a 404).
    @Test func receiptNotFoundMeansNoReceiptYet() async throws {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail": "No update receipt found (no `hermes update` run recorded)."}"#)
        let receipt = try await makeClient(http).hermesUpdateReceipt()
        #expect(receipt == nil)
    }

    @Test func untypedAnswersKeepTheirKeys() async throws {
        let stats = try await answer(#"{"cpu_percent": 12.5, "memory": {"total": 16766410752}}"#) {
            try await $0.systemStats()
        }
        #expect(stats == .object(["cpu_percent": .double(12.5), "memory": .object(["total": .int(16_766_410_752)])]))
    }
}
