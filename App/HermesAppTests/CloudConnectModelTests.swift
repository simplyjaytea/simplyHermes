import HermesKit
import HermesUI
import Testing

/// WP-17: the Hermes Cloud sheet's model over a stub sign-in, portal and connection test. These prove the order of
/// the steps and what is saved; they say nothing about the real portal, which is untested live.
@MainActor
struct CloudConnectModelTests {
    private let acme = CloudOrganization(id: "org_acme", name: "Acme Research")
    private let home = CloudOrganization(id: "org_home", name: "Home lab")
    private let bot = cloudAgent("agt_bot", "research-bot")
    private let night = cloudAgent("agt_night", "Night shift")

    @Test func signsInTakesTheOnlyOrganizationAndConnectsTheChosenAgent() async throws {
        let harness = Harness(organizations: [acme], agents: [acme.id: [bot, night]])

        harness.model.signIn()
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .chooseAgent)
        #expect(harness.model.selection.organization == acme)
        #expect(harness.signIns.calls.count == 1)
        #expect(harness.signIns.calls.first?.provider == "nous")
        #expect(harness.signIns.calls.first?.endpoint == NousPortalClient.portalEndpoint)
        #expect(harness.connections.connections.isEmpty, "Signing in saves nothing")

        harness.model.chooseAgent(night.id)
        harness.model.connect()
        await harness.model.waitUntilIdle()

        let saved = try #require(harness.connections.connections.first)
        #expect(harness.connections.connections.count == 1)
        #expect(saved.name == "Night shift")
        #expect(saved.cloudOrigin == CloudOrigin(organization: acme, agent: night))
        #expect(harness.connected.names == ["Night shift"])
        let tested = await harness.script.testedTokens
        #expect(tested == ["portal-token"], "The agent is tested with the sign-in's tokens")
        let stored = await harness.connections.secrets(for: saved, reason: "Test")
        #expect(stored?.nativeTokens?.accessToken == "portal-token", "The tokens that passed the test are kept")
    }

    @Test func anAgentThatWantsItsOwnSignInGetsOneAndThenConnects() async throws {
        let harness = Harness(
            organizations: [acme], agents: [acme.id: [bot]],
            testOutcomes: [.signInRequired(providers: ["nous"]), nil])
        harness.model.signIn()
        await harness.model.waitUntilIdle()

        harness.model.connect()
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .problem(.agentSignInRejected(agent: "research-bot")))
        #expect(harness.connections.connections.isEmpty)

        harness.model.perform(.signInToAgent)
        await harness.model.waitUntilIdle()

        #expect(harness.signIns.calls.count == 2)
        #expect(harness.signIns.calls.last?.endpoint == bot.endpoint, "The second sign-in goes to the agent")
        #expect(harness.signIns.calls.last?.provider == "nous")
        let tested = await harness.script.testedTokens
        #expect(tested == ["portal-token", "agent-token"])
        let saved = try #require(harness.connections.connections.first)
        #expect(harness.connections.connections.count == 1)
        let stored = await harness.connections.secrets(for: saved, reason: "Test")
        #expect(stored?.nativeTokens?.accessToken == "agent-token")
        #expect(harness.connected.names == ["research-bot"])
    }

    @Test func closingTheAgentSignInSheetReturnsToTheOfferToSignIn() async {
        let harness = Harness(
            organizations: [acme], agents: [acme.id: [bot]], agentSignIn: .failure(NativeSignInError.cancelled),
            testOutcomes: [.wrongCredentials])
        harness.model.signIn()
        await harness.model.waitUntilIdle()
        harness.model.connect()
        await harness.model.waitUntilIdle()

        harness.model.perform(.signInToAgent)
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .problem(.agentSignInRejected(agent: "research-bot")))
        #expect(harness.connections.connections.isEmpty)
    }

    @Test func severalOrganizationsWaitForAPickBeforeTheirAgentsLoad() async {
        let harness = Harness(organizations: [acme, home], agents: [acme.id: [bot], home.id: [night]])

        harness.model.signIn()
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .chooseOrganization)
        #expect(harness.model.selection.agents.isEmpty)

        harness.model.chooseOrganization(home.id)
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .chooseAgent)
        #expect(harness.model.selection.organization == home)
        #expect(harness.model.selection.agent == night, "The only agent is preselected, but nothing connects yet")
        #expect(harness.connections.connections.isEmpty)
    }

    @Test func aFailedTestSavesNothingAndTryAgainConnects() async {
        let harness = Harness(
            organizations: [acme], agents: [acme.id: [bot]],
            testOutcomes: [.serverTooOld(found: "release 2026.1.1"), nil])
        harness.model.signIn()
        await harness.model.waitUntilIdle()

        harness.model.connect()
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .problem(.agentTooOld(agent: "research-bot", found: "release 2026.1.1")))
        #expect(harness.connections.connections.isEmpty, "A failing agent is never saved")
        #expect(harness.connected.names.isEmpty)
        #expect(harness.model.canReturnToAgents)

        harness.model.perform(.retry)
        await harness.model.waitUntilIdle()
        #expect(harness.connections.connections.count == 1)
        #expect(harness.connected.names == ["research-bot"])
    }

    @Test func closingTheSignInSheetStaysOnTheSignInStep() async {
        let harness = Harness(organizations: [acme], signIn: .failure(NativeSignInError.cancelled))

        harness.model.signIn()
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .signIn)
        #expect(harness.signIns.calls.count == 1)
    }

    @Test func aRefusedSignInIsAProblemWithSignInAgain() async {
        let harness = Harness(organizations: [acme], signIn: .failure(NativeSignInError.codeRejected))

        harness.model.signIn()
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .problem(.signInFailed("")))
    }

    @Test func anUnreachablePortalIsAProblemNotAnEmptyList() async {
        let harness = Harness(organizations: [acme], portalFailure: .unreachable("offline"))

        harness.model.signIn()
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .problem(.portalUnreachable("offline")))
        #expect(harness.model.selection.organizations.isEmpty)
    }

    @Test func aRevokedOrganizationIsDroppedAndTheOthersStayListed() async {
        let harness = Harness(
            organizations: [acme, home], agents: [home.id: [night]], revokedOrganizations: [acme.id])
        harness.model.signIn()
        await harness.model.waitUntilIdle()

        harness.model.chooseOrganization(acme.id)
        await harness.model.waitUntilIdle()
        #expect(harness.model.step == .problem(.organizationRevoked(organization: "Acme Research")))
        #expect(harness.model.selection.organizations == [home])

        harness.model.perform(.chooseOrganization)
        #expect(harness.model.step == .chooseOrganization, "The one that is left waits for a pick")
    }

    @Test func anOrganizationWithoutAgentsIsAProblem() async {
        let harness = Harness(organizations: [acme], agents: [acme.id: []])

        harness.model.signIn()
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .problem(.noAgents(organization: "Acme Research")))
    }

    @Test func anAgentThatIsSavedAlreadyIsRefreshedNotAddedTwice() async throws {
        let existing = ServerConnection.cloud(organization: acme, agent: bot, saved: SavedConnections())
        var saved = SavedConnections()
        saved.upsert(existing)
        let harness = Harness(organizations: [acme], agents: [acme.id: [bot]], saved: saved)

        harness.model.signIn()
        await harness.model.waitUntilIdle()
        #expect(harness.model.isSaved(bot))

        harness.model.connect()
        await harness.model.waitUntilIdle()

        let all = harness.connections.connections
        #expect(all.count == 1)
        #expect(all.first?.id == existing.id)
        #expect(harness.connected.names == ["research-bot"])
    }

    @Test func checkingAgainBeforeSigningInAsksForTheSignIn() async {
        let harness = Harness(organizations: [acme])

        harness.model.perform(.checkAgain)
        await harness.model.waitUntilIdle()

        #expect(harness.model.step == .problem(.notSignedIn))
    }
}

// MARK: - Stubs

private func cloudAgent(_ id: String, _ name: String) -> CloudAgent {
    guard let endpoint = HermesEndpoint(string: "https://\(id).agents.example") else {
        preconditionFailure("The test address is valid")
    }
    return CloudAgent(id: id, name: name, status: .running, endpoint: endpoint)
}

/// Answers the browser sign-ins in order (the last answer repeats) and remembers where each one went.
@MainActor
private final class SignInLog {
    var calls: [(endpoint: HermesEndpoint, provider: String?)] = []
    private var outcomes: [Result<BrowserSignInResult, any Error>]

    init(_ outcomes: [Result<BrowserSignInResult, any Error>]) {
        self.outcomes = outcomes
    }

    func next(endpoint: HermesEndpoint, provider: String?) throws -> BrowserSignInResult {
        calls.append((endpoint, provider))
        let outcome = outcomes.count > 1 ? outcomes.removeFirst() : outcomes[0]
        return try outcome.get()
    }
}

@MainActor
private final class ConnectedLog {
    var names: [String] = []
}

private struct StubSignIn: BrowserSigningIn {
    let log: SignInLog

    @MainActor
    func signIn(
        endpoint: HermesEndpoint, options: SignInOptions?, provider: String?
    ) async throws -> BrowserSignInResult {
        try log.next(endpoint: endpoint, provider: provider)
    }
}

private struct ScriptedPortal: CloudPortalClient {
    let listedOrganizations: [CloudOrganization]
    let agentsByOrganization: [String: [CloudAgent]]
    let failure: CloudPortalError?
    let revokedOrganizations: Set<String>

    var endpoint: HermesEndpoint { NousPortalClient.portalEndpoint }

    func organizations(accessToken: String) async throws -> [CloudOrganization] {
        if let failure { throw failure }
        return listedOrganizations
    }

    func agents(in organization: CloudOrganization, accessToken: String) async throws -> [CloudAgent] {
        if revokedOrganizations.contains(organization.id) { throw CloudPortalError.organizationRevoked(organization) }
        return agentsByOrganization[organization.id] ?? []
    }
}

/// Answers each connection test from a list: nil passes, a failure throws. Remembers the tokens it was given.
private actor TesterScript {
    private var outcomes: [ConnectionTestFailure?]
    private(set) var testedTokens: [String] = []

    init(_ outcomes: [ConnectionTestFailure?]) {
        self.outcomes = outcomes
    }

    func next(_ secrets: ConnectionSecrets) -> ConnectionTestFailure? {
        if let token = secrets.nativeTokens?.accessToken { testedTokens.append(token) }
        return outcomes.isEmpty ? nil : outcomes.removeFirst()
    }
}

private struct ScriptedTester: ConnectionTesting {
    let script: TesterScript

    func test(
        _ connection: ServerConnection, secrets: ConnectionSecrets,
        progress: @escaping @Sendable (ConnectionTestStep) -> Void,
        confirmHostKey: @escaping @Sendable (HostKeyFingerprint) async -> Bool
    ) async throws -> ConnectionTestReport {
        progress(.reachingServer)
        if let failure = await script.next(secrets) { throw failure }
        return ConnectionTestReport(serverVersion: "git.d97007c", releaseDate: "2026.9.24")
    }
}

/// A model wired to the stubs, and what they saw.
@MainActor
private final class Harness {
    let model: CloudConnectModel
    let connections: ConnectionsModel
    let signIns: SignInLog
    let connected = ConnectedLog()
    let script: TesterScript

    /// `signIn` answers the first browser sign-in (Hermes Cloud), `agentSignIn` the second (an agent's own). By
    /// default they give tokens named `portal-token` and `agent-token`.
    init(
        organizations: [CloudOrganization], agents: [String: [CloudAgent]] = [:],
        signIn: Result<BrowserSignInResult, any Error>? = nil,
        agentSignIn: Result<BrowserSignInResult, any Error>? = nil,
        portalFailure: CloudPortalError? = nil, revokedOrganizations: Set<String> = [],
        testOutcomes: [ConnectionTestFailure?] = [], saved: SavedConnections = SavedConnections()
    ) {
        func tokens(_ access: String) -> Result<BrowserSignInResult, any Error> {
            .success(.tokens(NativeTokens(accessToken: access, refreshToken: "r", expiresAt: 0, provider: "nous")))
        }
        signIns = SignInLog([signIn ?? tokens("portal-token"), agentSignIn ?? tokens("agent-token")])
        script = TesterScript(testOutcomes)
        let services = ConnectionServices(
            credentials: InMemoryCredentialStore(), gatewayTester: ScriptedTester(script: script),
            sshTester: ScriptedTester(script: script), unlocker: AlwaysUnlocked(),
            browserSignIn: StubSignIn(log: signIns), offline: true,
            cloudPortal: ScriptedPortal(
                listedOrganizations: organizations, agentsByOrganization: agents, failure: portalFailure,
                revokedOrganizations: revokedOrganizations))
        connections = ConnectionsModel(store: nil, services: services, initial: saved)
        let log = connected
        model = CloudConnectModel(connections: connections, onConnected: { log.names.append($0.name) })
    }
}
