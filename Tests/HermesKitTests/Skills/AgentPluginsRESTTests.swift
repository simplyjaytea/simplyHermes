import Foundation
import HermesKit
import Testing

/// Agent plugin calls: the hub and catalog reads, install from git or catalog (with the commit pin), enable and disable,
/// update with consent, remove and activate. Every request carries the active profile, like the other calls.
@Suite struct AgentPluginsRESTTests {
    @Test func hubListsPluginsWithTheirRuntimeStatus() async throws {
        let (hub, request) = try await skillsRun("agent_plugins_hub") { try await $0.agentPluginHub() }
        #expect(hub.plugins.map(\.name) == ["example-tools", "example-memory"])
        #expect(hub.plugins.first?.isEnabled == true && hub.plugins.last?.isEnabled == false)
        #expect(hub.plugins.first?.canRemove == true && hub.plugins.first?.canUpdateGit == true)
        #expect(hub.plugins.last?.canRemove == false && hub.plugins.last?.authRequired == true)
        #expect(hub.plugins.first?.source == "git" && hub.plugins.first?.version == "1.2.0")
        #expect(request.method == "GET" && request.url.path == "/api/dashboard/plugins/hub")
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func catalogCarriesThePinAndTheInstalledState() async throws {
        let (catalog, request) = try await skillsRun("agent_plugins_catalog") { try await $0.agentPluginCatalog() }
        let first = try #require(catalog.entries.first)
        #expect(first.name == "example-tools" && first.title == "Example Tools")
        #expect(first.sha == "0123456789abcdef0123456789abcdef01234567" && first.shaShort == "0123456")
        #expect(first.installed == true && first.installedSha == "fedcba9876543210fedcba9876543210fedcba98")
        #expect(first.updateAvailable == true && first.runtimeStatus == "enabled")
        #expect(
            first.capabilities?.providesTools == ["example_lookup"]
                && first.capabilities?.requiresEnv == ["EXAMPLE_TOKEN"])
        #expect(catalog.entries.last?.subdir == "plugins/kit" && catalog.entries.last?.installed == false)
        #expect(catalog.removed?.first?.reason == "Superseded" && catalog.generatedAt == "2026-10-18T09:00:00Z")
        #expect(request.url.path == "/api/dashboard/plugins/catalog")
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func rescanReadsTheCount() async throws {
        let (rescan, request) = try await skillsRun("agent_plugin_rescan") { try await $0.rescanAgentPlugins() }
        #expect(rescan.ok == true && rescan.count == 2)
        #expect(request.method == "GET" && request.url.path == "/api/dashboard/plugins/rescan")
    }

    @Test func installFromGitSendsTheCommitPin() async throws {
        let pin = "0123456789abcdef0123456789abcdef01234567"
        let request = AgentPluginInstallRequest(identifier: "https://git.example.com/tools.git#plugins/x", ref: pin)
        let (result, sent) = try await skillsRun("agent_plugin_installed") { try await $0.installAgentPlugin(request) }
        #expect(result.ok == true && result.pluginName == "example-tools" && result.enabled == true)
        #expect(result.missingEnv == ["EXAMPLE_TOKEN"] && result.restartRequired == false)
        #expect(sent.method == "POST" && sent.url.path == "/api/dashboard/agent-plugins/install")
        let body = try skillsJSONBody(sent)
        #expect(body["identifier"] as? String == "https://git.example.com/tools.git#plugins/x")
        #expect(body["ref"] as? String == pin && body["force"] as? Bool == false && body["enable"] as? Bool == true)
        #expect(body["catalog_name"] == nil, "a git install sends no catalog name")
        #expect(skillsQuery(sent) == ["profile": "ops"])
    }

    @Test func installFromCatalogSendsTheNameAndAnEmptyIdentifier() async throws {
        let request = AgentPluginInstallRequest(catalogName: "example-tools", force: true, enable: false)
        let (_, sent) = try await skillsRun("agent_plugin_installed") { try await $0.installAgentPlugin(request) }
        let body = try skillsJSONBody(sent)
        #expect(body["identifier"] as? String == "")
        #expect(body["catalog_name"] as? String == "example-tools")
        #expect(body["force"] as? Bool == true && body["enable"] as? Bool == false)
        #expect(body["ref"] == nil)
    }

    @Test func commitPinNeedsAFullCommitID() {
        #expect(AgentPluginInstallRequest.isCommitSHA("0123456789abcdef0123456789abcdef01234567"))
        #expect(AgentPluginInstallRequest.isCommitSHA("0123456789ABCDEF0123456789abcdef01234567"))
        #expect(!AgentPluginInstallRequest.isCommitSHA("0123456"), "a short id is refused")
        #expect(!AgentPluginInstallRequest.isCommitSHA("0123456789abcdef0123456789abcdef0123456g"))
        #expect(!AgentPluginInstallRequest.isCommitSHA("main"))
    }

    @Test func enableAndDisableEncodeTheNameAsOneSegment() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"owner/plugin","unchanged":false,"restart_required":true}"#)
        http.enqueue(200, #"{"ok":true,"name":"example-tools","unchanged":false}"#)
        let client = makeClient(http, profile: "ops")
        let disabled = try await client.setAgentPluginEnabled("owner/plugin", enabled: false)
        _ = try await client.setAgentPluginEnabled("example-tools", enabled: true)
        #expect(disabled.restartRequired == true && disabled.unchanged == false)
        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "POST"])
        #expect(requests[0].url.path == "/api/dashboard/agent-plugins/owner%2Fplugin/disable")
        #expect(requests[1].url.path == "/api/dashboard/agent-plugins/example-tools/enable")
        #expect(requests.allSatisfy { skillsQuery($0) == ["profile": "ops"] })
    }

    @Test func updateSendsTheConsentFlagAndReadsTheDelta() async throws {
        let (consent, request) = try await skillsRun("agent_plugin_consent", status: 200) {
            try await $0.updateAgentPlugin("example-tools")
        }
        #expect(consent.consentRequired == true && consent.ok == false)
        #expect(consent.deltaLines == ["registers tool(s): example_upload"])
        #expect(consent.sha == "2222222222222222222222222222222222222222", "the answer names the pin it would move to")
        #expect(request.url.path == "/api/dashboard/agent-plugins/example-tools/update")
        let body = try skillsJSONBody(request)
        #expect(body.count == 1 && body["accept_capabilities"] as? Bool == false)

        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"example-tools","output":"Already up to date.","unchanged":true}"#)
        let client = makeClient(http, profile: "ops")
        let updated = try await client.updateAgentPlugin("example-tools", acceptCapabilities: true)
        #expect(updated.ok == true && updated.unchanged == true && updated.output == "Already up to date.")
        let sent = try #require(http.requests.first)
        #expect(try skillsJSONBody(sent)["accept_capabilities"] as? Bool == true)
    }

    @Test func removeDeletesTheInstall() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"name":"example-tools"}"#)
        let client = makeClient(http, profile: "ops")
        let removed = try await client.removeAgentPlugin("example-tools")
        #expect(removed.ok == true && removed.name == "example-tools")
        let request = try #require(http.requests.first)
        #expect(request.method == "DELETE" && request.url.path == "/api/dashboard/agent-plugins/example-tools")
        #expect(request.body == nil)
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func activateSendsTheProfileHome() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"ok":true,"activation":{"live":true}}"#)
        let client = makeClient(http, profile: "ops")
        let result = try await client.activateAgentPlugin("example-tools", home: "/home/hermes/.hermes/profiles/ops")
        #expect(result.ok == true)
        let request = try #require(http.requests.first)
        #expect(request.method == "POST" && request.url.path == "/api/dashboard/agent-plugins/activate")
        let body = try skillsJSONBody(request)
        #expect(body["name"] as? String == "example-tools")
        #expect(body["home"] as? String == "/home/hermes/.hermes/profiles/ops")
    }
}
