import Foundation
import HermesKit
import Testing

@Suite struct GatewaySetupTests {
    private let tailscale = GatewaySetup.Address(host: .tailscale, usesHTTPS: true)
    private let loopback = GatewaySetup.Address(host: .loopback, usesHTTPS: false)

    private func failedCheck(_ status: GatewaySetup.Status?) -> GatewaySetup.Check? {
        guard case .failed(let diagnosis)? = status else { return nil }
        return diagnosis.check
    }

    @Test func promptKeepsTheGuardrails() {
        let prompt = GatewaySetup.prompt
        #expect(prompt.contains("Never run `hermes serve --stop`"))
        #expect(prompt.contains("Never run `tailscale funnel`"))
        #expect(prompt.contains("Never bind Hermes to 127.0.0.1 or 0.0.0.0"))
        #expect(prompt.contains("sudo tailscale serve --bg --https=443 http://<TS_IP>:9119"))
        #expect(prompt.contains("\"auth_required\": true"))
        #expect(!prompt.contains("--host 0.0.0.0"))
    }

    @Test func promptLinkIsOneTheScannerAccepts() throws {
        // The agent prints `simplyhermes://add?...` with its own host. Filled in, the app must read it.
        let line = try #require(
            GatewaySetup.prompt.split(separator: "\n").first { $0.contains("simplyhermes://add?") })
        let query = try #require(line.components(separatedBy: "simplyhermes://").last)
        let link = "simplyhermes://" + query.replacingOccurrences(of: "<HOST>", with: "box.tail1234.ts.net")
        #expect(
            ConnectionQRCode(scanned: link)
                == .gateway(url: "https://box.tail1234.ts.net", name: "Home", username: "hermes"))
    }

    @Test func statusesFollowTheTestProgress() {
        let reaching = GatewaySetup.statuses(stage: .reachingServer, failure: nil, passed: false, address: nil)
        #expect(reaching[.reach] == .running)
        #expect(reaching[.hermes] == .pending)

        let signing = GatewaySetup.statuses(stage: .signingIn, failure: nil, passed: false, address: nil)
        #expect(signing[.reach] == .passed)
        #expect(signing[.hermes] == .passed)
        #expect(signing[.signIn] == .running)
        #expect(signing[.live] == .pending)

        let socket = GatewaySetup.statuses(stage: .openingWebSocket, failure: nil, passed: false, address: nil)
        #expect(socket[.signIn] == .passed)
        #expect(socket[.live] == .running)

        let done = GatewaySetup.statuses(stage: .openingWebSocket, failure: nil, passed: true, address: nil)
        #expect(GatewaySetup.Check.allCases.allSatisfy { done[$0] == .passed })
    }

    @Test func aFailureMarksItsCheckAndLeavesTheRest() {
        let wrong = GatewaySetup.statuses(stage: .signingIn, failure: .wrongCredentials, passed: false, address: nil)
        #expect(wrong[.reach] == .passed)
        #expect(failedCheck(wrong[.signIn]) == .signIn)
        #expect(wrong[.live] == .pending)

        let refused = GatewaySetup.statuses(
            stage: .reachingServer, failure: .unreachable("refused"), passed: false, address: tailscale)
        #expect(failedCheck(refused[.reach]) == .reach)
        #expect(refused[.hermes] == .pending)

        let notHermes = GatewaySetup.statuses(stage: .reachingServer, failure: .notHermes, passed: false, address: nil)
        #expect(notHermes[.reach] == .passed, "Something answered, so the address was reached")
        #expect(failedCheck(notHermes[.hermes]) == .hermes)

        let socket = GatewaySetup.statuses(
            stage: .openingWebSocket, failure: .webSocket("closed"), passed: false, address: nil)
        #expect(failedCheck(socket[.live]) == .live)
        #expect(socket[.signIn] == .passed)
    }

    @Test func aFailureOutsideTheChecksLeavesThemPending() {
        let form = GatewaySetup.statuses(
            stage: .reachingServer, failure: .invalidForm("Enter the user name."), passed: false, address: nil)
        #expect(GatewaySetup.Check.allCases.allSatisfy { form[$0] == .pending })
    }

    @Test func reachFailuresDependOnWhereTheAddressSits() {
        let phone = GatewaySetup.diagnosis(for: .unreachable("refused"), check: .reach, address: loopback)
        #expect(phone.message.contains("this iPhone"))
        #expect(GatewaySetup.loopbackNote(for: loopback.host) != nil)

        let secure = GatewaySetup.diagnosis(for: .unreachable("refused"), check: .reach, address: tailscale)
        #expect(secure.fixes.contains { $0.contains("Turn on Tailscale") })
        #expect(secure.fixes.contains { $0.contains("HTTPS Certificates") })

        let plain = GatewaySetup.Address(host: .tailscale, usesHTTPS: false)
        let plainDiagnosis = GatewaySetup.diagnosis(for: .unreachable("refused"), check: .reach, address: plain)
        #expect(!plainDiagnosis.fixes.contains { $0.contains("HTTPS Certificates") })

        let home = GatewaySetup.Address(host: .privateNetwork, usesHTTPS: false)
        let homeDiagnosis = GatewaySetup.diagnosis(for: .unreachable("refused"), check: .reach, address: home)
        #expect(homeDiagnosis.fixes.contains { $0.contains("Local Network") })
        #expect(GatewaySetup.loopbackNote(for: home.host) == nil)
        #expect(GatewaySetup.loopbackNote(for: nil) == nil)
        #expect(GatewaySetup.loopbackNote(for: .publicInternet) == nil)
    }

    @Test func typedAddressGivesTheHints() {
        #expect(
            GatewaySetup.Address(typed: "https://box.tail1234.ts.net")
                == GatewaySetup.Address(host: .tailscale, usesHTTPS: true))
        #expect(
            GatewaySetup.Address(typed: "http://127.0.0.1:9119")
                == GatewaySetup.Address(host: .loopback, usesHTTPS: false))
        #expect(GatewaySetup.Address(typed: "ftp://box") == nil)
        #expect(GatewaySetup.Address(typed: "   ") == nil)
    }

    @Test func signInAndVersionWordsNameTheFix() {
        let wrong = GatewaySetup.diagnosis(for: .wrongCredentials, check: .signIn, address: tailscale)
        #expect(wrong.fixes.contains { $0.contains("dashboard.env") })

        let old = GatewaySetup.diagnosis(for: .serverTooOld(found: "git.0123456"), check: .hermes, address: nil)
        #expect(old.message.contains("too old"))
        #expect(old.fixes.contains { $0.contains("hermes update") })
    }
}
