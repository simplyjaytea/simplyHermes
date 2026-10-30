import Foundation
import HermesKit
import Testing

/// Collects values from a `@Sendable` closure in a test.
private final class Recorder<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Value] = []

    func append(_ value: Value) {
        lock.withLock { stored.append(value) }
    }

    var values: [Value] { lock.withLock { stored } }
}

/// Skill, hub and background-action calls. Each test decodes a fixture written from the server's own code and checks the
/// request: the path, the body keys the server's request model expects, and the `profile` scope.
@Suite struct SkillsRESTTests {
    @Test func contentReadAndWriteAreScopedAndEncoded() async throws {
        let (content, read) = try await skillsRun("skill_content") { try await $0.skillContent("claude-code") }
        #expect(content.name == "claude-code" && content.content.contains("# Claude Code"))
        #expect(content.path?.hasSuffix("SKILL.md") == true)
        #expect(read.method == "GET" && read.url.path == "/api/skills/content")
        #expect(skillsQuery(read) == ["name": "claude-code", "profile": "ops"])

        let (write, saved) = try await skillsRun("skill_write") {
            try await $0.updateSkillContent("claude-code", content: "---\nname: claude-code\n---\n")
        }
        #expect(write.success == true && write.systemPromptPreview?.isEmpty == false)
        #expect(saved.method == "PUT" && saved.url.path == "/api/skills/content")
        let body = try skillsJSONBody(saved)
        #expect(body["name"] as? String == "claude-code")
        #expect(body["content"] as? String == "---\nname: claude-code\n---\n")
        #expect(skillsQuery(saved) == ["profile": "ops"])
    }

    @Test func toggleSendsNameAndState() async throws {
        let (result, request) = try await skillsRun("skill_toggle") {
            try await $0.setSkillEnabled("codex", enabled: false)
        }
        #expect(result.ok == true && result.name == "codex" && result.enabled == false)
        #expect(request.method == "PUT" && request.url.path == "/api/skills/toggle")
        let body = try skillsJSONBody(request)
        #expect(body["name"] as? String == "codex" && body["enabled"] as? Bool == false)
        #expect(skillsQuery(request) == ["profile": "ops"])
    }

    @Test func createOmitsCategoryUnlessSet() async throws {
        let (created, plain) = try await skillsRun("skill_write") {
            try await $0.createSkill("notes", content: "---\nname: notes\n---\n")
        }
        #expect(created.success == true && plain.method == "POST" && plain.url.path == "/api/skills")
        let plainBody = try skillsJSONBody(plain)
        #expect(plainBody["category"] == nil && plainBody["name"] as? String == "notes")

        let http = FakeHTTP()
        http.enqueue(200, #"{"success":true,"message":"created"}"#)
        let client = makeClient(http, profile: "ops")
        _ = try await client.createSkill("notes", content: "x", category: "devops")
        let sent = try #require(http.requests.first)
        #expect(try skillsJSONBody(sent)["category"] as? String == "devops")
    }

    @Test func hubCatalogAndSourcesKeepIdentifiersAsTheyAre() async throws {
        let (official, catalogRequest) = try await skillsRun("skill_hub_official") {
            try await $0.officialSkillCatalog()
        }
        #expect(official.skills.map(\.name) == ["arxiv", "docker-management"])
        #expect(
            official.skills.first?.identifier == "official/research/arxiv" && official.skills.last?.installed == true)
        #expect(official.skills.first?.category == "research" && official.skills.first?.trustLevel == "builtin")
        #expect(catalogRequest.method == "GET" && catalogRequest.url.path == "/api/skills/hub/official")

        let (sources, sourcesRequest) = try await skillsRun("skill_hub_sources") { try await $0.skillHubSources() }
        #expect(sources.sources.map(\.id) == ["official", "github", "hermes-index"])
        #expect(sources.indexAvailable == true && sources.sources.last?.available == true)
        #expect(sources.featured?.first?.id == "official/research/arxiv")
        // Installed identifiers are dictionary keys. They must come back unchanged, with the underscores in them.
        #expect(sources.installed?["official/devops/docker-management"]?.scanVerdict == "safe")
        #expect(
            sourcesRequest.url.path == "/api/skills/hub/sources" && skillsQuery(sourcesRequest) == ["profile": "ops"])
    }

    @Test func hubSearchSendsQueryAndDecodesCounts() async throws {
        let (search, request) = try await skillsRun("skill_hub_search") {
            try await $0.searchSkillHub("arxiv papers", limit: 5)
        }
        #expect(search.results.map(\.name) == ["arxiv", "paper-notes"])
        #expect(search.sourceCounts == ["official": 1, "github": 1] && search.timedOut == ["clawhub"])
        #expect(search.installed?.isEmpty == true, "an empty query answers installed as an empty object")
        #expect(skillsQuery(request) == ["q": "arxiv papers", "source": "all", "limit": "5", "profile": "ops"])
        #expect(request.url.query?.contains("q=arxiv%20papers") == true)
    }

    @Test func previewAndScanUseTheIdentifierQuery() async throws {
        let identifier = "official/research/arxiv"
        let (preview, previewRequest) = try await skillsRun("skill_hub_preview") {
            try await $0.previewSkillHub(identifier)
        }
        #expect(preview.files == ["SKILL.md", "references/query-syntax.md"])
        #expect(preview.skillMd?.contains("# arXiv") == true)
        #expect(skillsQuery(previewRequest)["identifier"] == identifier)

        let (scan, scanRequest) = try await skillsRun("skill_hub_scan") {
            try await $0.scanSkillHub("github/example-org/paper-notes")
        }
        #expect(scan.policy == "ask" && scan.verdict == "caution")
        #expect(scan.findings?.first?.line == 12 && scan.severityCounts?["medium"] == 1)
        #expect(skillsQuery(scanRequest)["identifier"] == "github/example-org/paper-notes")
        #expect(scanRequest.url.path == "/api/skills/hub/scan")
    }

    @Test func installUninstallAndUpdateStartActions() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("action_started"))
        http.enqueue(200, try restFixture("action_started"))
        http.enqueue(200, try restFixture("action_started"))
        let client = makeClient(http, profile: "ops")

        let started = try await client.installHubSkill("official/research/arxiv")
        _ = try await client.uninstallHubSkill("arxiv")
        _ = try await client.updateHubSkills()
        #expect(started.name == "skills-install-arxiv-1a2b3c4d" && started.pid == 4242)

        let requests = http.requests
        #expect(requests.map(\.method) == ["POST", "POST", "POST"])
        #expect(
            requests.map(\.url.path) == [
                "/api/skills/hub/install", "/api/skills/hub/uninstall", "/api/skills/hub/update",
            ])
        let installBody = try skillsJSONBody(requests[0])
        #expect(installBody.count == 1 && installBody["identifier"] as? String == "official/research/arxiv")
        let uninstallBody = try skillsJSONBody(requests[1])
        #expect(uninstallBody.count == 1 && uninstallBody["name"] as? String == "arxiv")
        #expect(requests[2].body == nil, "the update takes no body")
        #expect(requests.allSatisfy { skillsQuery($0) == ["profile": "ops"] })
    }

    @Test func actionStatusPollsUntilTheProcessEnds() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("action_status_running"))
        http.enqueue(200, try restFixture("action_status_finished"))
        let client = makeClient(http, profile: "ops")
        let seen = Recorder<Bool>()
        let poller = ServerActionPoller(interval: .zero, maxPolls: 5)
        let final = try await poller.finish("skills-install-arxiv-1a2b3c4d", rest: client) { status in
            seen.append(status.isRunning)
        }
        #expect(seen.values == [true, false] && final.succeeded && final.exitCode == 0)
        #expect(final.lines?.last == "Installed arxiv")
        let first = try #require(http.requests.first)
        #expect(first.url.path == "/api/actions/skills-install-arxiv-1a2b3c4d/status")
        #expect(skillsQuery(first) == ["lines": "200", "profile": "ops"])
    }

    @Test func pollerGivesUpAfterTheLimit() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try restFixture("action_status_running"))
        http.enqueue(200, try restFixture("action_status_running"))
        let client = makeClient(http, profile: nil)
        let poller = ServerActionPoller(interval: .zero, maxPolls: 2)
        await #expect(throws: ServerActionTimeout(name: "skills-install-arxiv-1a2b3c4d")) {
            try await poller.finish("skills-install-arxiv-1a2b3c4d", rest: client)
        }
    }

    @Test func actionNamesAreEncodedAsOnePathSegment() async throws {
        let (status, request) = try await skillsRun("action_status_finished", profile: nil) {
            try await $0.actionStatus("a/b c")
        }
        #expect(status.succeeded && status.isRunning == false)
        #expect(
            URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.percentEncodedPath
                == "/api/actions/a%2Fb%20c/status")
        #expect(request.url.query == "lines=200", "no profile is sent when none is set")
    }

    @Test func provenanceReadsKnownLabelsOnly() {
        #expect(SkillProvenance(label: "hub") == .hub && SkillProvenance(label: "bundled") == .bundled)
        #expect(SkillProvenance(label: "external") == .external && SkillProvenance(label: "agent") == .agent)
        #expect(SkillProvenance(label: "mystery") == .other && SkillProvenance(label: nil) == .other)
        #expect(SkillProvenance.hub.isHubInstall && !SkillProvenance.bundled.isHubInstall)
    }
}
