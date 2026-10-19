import Foundation
import HermesKit
import Testing

/// WP-17 CI gate: a cloud entry is a gateway with an origin, deduped by organization id plus agent id, and files
/// saved before WP-17 still load.
@Suite struct CloudConnectionTests {
    private let acme = org("org_acme", "Acme")
    private let bot = agent("agt_1", "research-bot", host: "bot")

    private func plainGateway(_ url: String, name: String) -> ServerConnection {
        ServerConnection(name: name, kind: .gateway(GatewaySettings(endpoint: HermesEndpoint(string: url)!)))
    }

    @Test func aCloudEntryIsAGatewayThatSignsInWithNous() throws {
        let connection = ServerConnection.cloud(organization: acme, agent: bot, saved: SavedConnections())
        guard case .gateway(let settings) = connection.kind else {
            Issue.record("A cloud entry must go through the gateway path")
            return
        }
        #expect(settings.endpoint == bot.endpoint)
        #expect(settings.signIn == .browser(provider: "nous"))
        #expect(!settings.remembersPassword)
        #expect(settings.cloud == CloudOrigin(organization: acme, agent: bot))
        #expect(connection.name == "research-bot")
        #expect(!connection.requiresUnlock && !connection.isSSH)
        #expect(connection.isCloud)
        #expect(connection.cloudOrigin?.agentName == "research-bot")
    }

    @Test func listRowsShowHermesCloudWithTheOrganizationAndAgent() {
        let connection = ServerConnection.cloud(organization: acme, agent: bot, saved: SavedConnections())
        #expect(connection.address == "Hermes Cloud · Acme · research-bot")
        #expect(!plainGateway("https://a.example", name: "A").isCloud)
        #expect(plainGateway("https://a.example", name: "A").address == "https://a.example")
    }

    @Test func dedupesByOrganizationPlusAgentId() {
        var saved = SavedConnections()
        let first = ServerConnection.cloud(organization: acme, agent: bot, saved: saved)
        saved.upsert(first)

        let sameAgentLaterOnAnotherAddress = ServerConnection(
            name: "Again",
            kind: .gateway(
                GatewaySettings(
                    endpoint: HermesEndpoint(string: "https://moved.agents.example")!,
                    cloud: CloudOrigin(organization: acme, agent: bot))))
        #expect(saved.duplicate(of: sameAgentLaterOnAnotherAddress)?.id == first.id)

        let otherOrganization = ServerConnection.cloud(organization: org("org_home", "Home"), agent: bot, saved: saved)
        #expect(
            saved.duplicate(of: otherOrganization) == nil, "The same agent id in another organization is another agent")
        let otherAgent = ServerConnection.cloud(organization: acme, agent: agent("agt_2", "other"), saved: saved)
        #expect(saved.duplicate(of: otherAgent) == nil)
        #expect(saved.duplicate(of: first) == nil, "An entry is not its own duplicate")
    }

    @Test func aTypedGatewayAtTheSameAddressIsNotACloudDuplicate() {
        var saved = SavedConnections()
        saved.upsert(plainGateway(bot.endpoint.baseURL.absoluteString, name: "Typed"))
        let cloud = ServerConnection.cloud(organization: acme, agent: bot, saved: saved)
        #expect(saved.duplicate(of: cloud) == nil)
        #expect(cloud.dedupeKey == "cloud org_acme/agt_1")
    }

    @Test func addingASavedAgentAgainRefreshesTheEntry() {
        var saved = SavedConnections()
        var first = ServerConnection.cloud(
            organization: acme, agent: bot, saved: saved, now: Date(timeIntervalSince1970: 100))
        first.name = "My bot"
        first.requiresUnlock = true
        saved.upsert(first)
        #expect(saved.contains(agent: bot, in: acme))

        let moved = CloudAgent(
            id: bot.id, name: "renamed", status: .running,
            endpoint: HermesEndpoint(string: "https://moved.agents.example")!)
        let again = ServerConnection.cloud(organization: acme, agent: moved, saved: saved)
        #expect(again.id == first.id, "Same entry, so saving replaces it")
        #expect(again.name == "My bot", "The user's name for it stays")
        #expect(again.requiresUnlock)
        #expect(again.createdAt == Date(timeIntervalSince1970: 100))
        #expect(again.address.hasSuffix("renamed"), "The origin shows the latest names")
        guard case .gateway(let settings) = again.kind else { return }
        #expect(settings.endpoint.baseURL.host == "moved.agents.example")
        saved.upsert(again)
        #expect(saved.connections.count == 1)
    }

    @Test func namesAreMadeUniqueAmongTheSavedOnes() {
        var saved = SavedConnections()
        saved.upsert(plainGateway("https://a.example", name: "assistant"))
        let first = ServerConnection.cloud(organization: acme, agent: agent("a1", "Assistant", host: "x"), saved: saved)
        #expect(first.name == "Assistant 2")
        saved.upsert(first)
        let second = ServerConnection.cloud(
            organization: org("org_home", "Home"), agent: agent("a9", "assistant", host: "y"), saved: saved)
        #expect(second.name == "assistant 3")
        let nameless = ServerConnection.cloud(organization: acme, agent: agent("a2", "  ", host: "z"), saved: saved)
        #expect(saved.nameProblem(nameless.name, for: nameless.id) == nil)
    }

    @Test func filesSavedBeforeWP17StillLoad() throws {
        let legacy = ServerConnection(
            name: "Home",
            kind: .gateway(
                GatewaySettings(endpoint: HermesEndpoint(string: "https://a.example")!, signIn: .sessionToken)))
        let data = try JSONEncoder().encode(legacy)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("cloud"), "Typed gateways write no cloud key")
        let decoded = try JSONDecoder().decode(ServerConnection.self, from: data)
        #expect(decoded == legacy && !decoded.isCloud)
    }

    @Test func theStoreKeepsTheOrigin() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("connections.json")
        let store = ConnectionStore(fileURL: file)
        var saved = SavedConnections()
        saved.upsert(ServerConnection.cloud(organization: acme, agent: bot, saved: saved))
        saved.upsert(plainGateway("https://a.example", name: "Typed"))
        try store.save(saved)
        let loaded = try store.load()
        #expect(loaded == saved)
        #expect(loaded.connections.first?.cloudOrigin == CloudOrigin(organization: acme, agent: bot))
        #expect(loaded.connections.last?.cloudOrigin == nil)
    }

    @Test func theOriginHoldsNamesAndIdsOnly() throws {
        let origin = CloudOrigin(organization: acme, agent: bot)
        let json = try #require(
            String(data: try JSONEncoder().encode(origin), encoding: .utf8))
        for key in ["organizationID", "organizationName", "agentID", "agentName"] { #expect(json.contains(key)) }
        #expect(!json.lowercased().contains("token"))
    }

    @Test func idsAreComparedAsWrittenApartFromSpaces() {
        let one = CloudOrigin(organizationID: " o1 ", organizationName: "A", agentID: "a1\n", agentName: "A")
        let two = CloudOrigin(organizationID: "o1", organizationName: "B", agentID: "a1", agentName: "B")
        let three = CloudOrigin(organizationID: "O1", organizationName: "A", agentID: "a1", agentName: "A")
        #expect(one.dedupeKey == two.dedupeKey)
        #expect(one.dedupeKey != three.dedupeKey)
    }
}
