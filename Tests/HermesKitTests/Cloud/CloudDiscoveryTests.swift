import Foundation
import HermesKit
import Testing

/// WP-17 CI gate: discovery stops where the user must pick, and every failure becomes a calm problem with a retry.
@Suite struct CloudDiscoveryTests {
    private func run(_ portal: StubPortal, from start: CloudSelection = .init()) async -> CloudDiscoveryResult {
        await CloudDiscovery(portal: portal).advance(start, accessToken: "tok")
    }

    @Test func oneOrganizationGoesStraightToItsAgents() async {
        let portal = StubPortal(
            organizations: .success([org("acme")]),
            agents: ["acme": .success([agent("a1"), agent("a2")])])
        let result = await run(portal)
        #expect(result.problem == nil)
        #expect(result.selection.stage == .chooseAgent(org("acme")))
        #expect(portal.calls == ["organizations", "agents:acme"])
    }

    @Test func oneOrganizationWithOneAgentIsReady() async {
        let portal = StubPortal(
            organizations: .success([org("acme")]), agents: ["acme": .success([agent("only")])])
        let result = await run(portal)
        #expect(result.selection.stage == .ready(org("acme"), agent("only")))
    }

    @Test func severalOrganizationsStopForAPick() async {
        let portal = StubPortal(
            organizations: .success([org("acme"), org("home")]),
            agents: ["home": .success([agent("h1")])])
        var result = await run(portal)
        #expect(result.problem == nil)
        #expect(result.selection.stage == .chooseOrganization)
        #expect(portal.calls == ["organizations"], "No agents are fetched before the pick")

        result.selection.chooseOrganization(id: "home")
        result = await run(portal, from: result.selection)
        #expect(result.selection.stage == .ready(org("home"), agent("h1")))
        #expect(portal.calls == ["organizations", "agents:home"], "Organizations are not fetched twice")
    }

    @Test func noOrganizationsIsAProblemWithACheckAgain() async {
        let result = await run(StubPortal(organizations: .success([])))
        #expect(result.problem == .noOrganizations)
        #expect(result.problem?.action == .checkAgain)
    }

    @Test func noAgentsIsAProblemNamingTheOrganization() async {
        let portal = StubPortal(organizations: .success([org("acme", "Acme")]), agents: ["acme": .success([])])
        let result = await run(portal)
        #expect(result.problem == .noAgents(organization: "Acme"))
        #expect(result.selection.stage == .noAgents(org("acme", "Acme")))
    }

    @Test func aRevokedOrganizationIsDroppedAndTheOthersStayListed() async {
        let portal = StubPortal(
            organizations: .success([org("acme", "Acme"), org("home", "Home")]),
            agents: ["acme": .failure(.organizationRevoked(org("acme", "Acme")))])
        var result = await run(portal)
        result.selection.chooseOrganization(id: "acme")
        result = await run(portal, from: result.selection)
        #expect(result.problem == .organizationRevoked(organization: "Acme"))
        #expect(result.problem?.action == .chooseOrganization)
        #expect(result.selection.organizations == [org("home", "Home")])
        #expect(result.selection.stage == .chooseOrganization)
    }

    @Test func aRevokedOnlyOrganizationLeavesNoOrganization() async {
        let portal = StubPortal(
            organizations: .success([org("acme", "Acme")]),
            agents: ["acme": .failure(.organizationRevoked(org("acme", "Acme")))])
        let result = await run(portal)
        #expect(result.problem == .organizationRevoked(organization: "Acme"))
        #expect(result.selection.stage == .noOrganizations)
    }

    @Test func anOrganizationThatVanishesOnRefreshIsRevoked() async {
        let portal = StubPortal(
            organizations: .success([org("acme", "Acme"), org("home", "Home")]),
            agents: ["acme": .success([agent("a1"), agent("a2")])])
        var result = await run(portal)
        result.selection.chooseOrganization(id: "acme")
        result = await run(portal, from: result.selection)
        #expect(result.selection.stage == .chooseAgent(org("acme", "Acme")))

        portal.setOrganizations(.success([org("home", "Home")]))
        result.selection.refresh()
        result = await run(portal, from: result.selection)
        #expect(result.problem == .organizationRevoked(organization: "Acme"))
        #expect(result.selection.stage == .chooseOrganization)
    }

    @Test func portalFailuresBecomeProblemsWithTheirOwnActions() async {
        let cases: [(CloudPortalError, CloudProblem)] = [
            (.notSignedIn, .notSignedIn),
            (.unreachable("offline"), .portalUnreachable("offline")),
            (.busy(retryAfter: 30), .portalBusy),
            (.unexpectedReply("status 404"), .unexpectedReply("status 404")),
        ]
        for (failure, problem) in cases {
            let result = await run(StubPortal(organizations: .failure(failure)))
            #expect(result.problem == problem)
            #expect(result.selection.stage == .needsOrganizations, "Nothing was loaded, so Try again starts over")
        }
        #expect(CloudProblem.notSignedIn.action == .signIn)
        #expect(CloudProblem.portalUnreachable("x").action == .retry)
    }

    @Test func aFailureOnTheAgentsStepKeepsTheOrganization() async {
        let portal = StubPortal(
            organizations: .success([org("acme")]), agents: ["acme": .failure(.unreachable("timed out"))])
        let result = await run(portal)
        #expect(result.problem == .portalUnreachable("timed out"))
        #expect(result.selection.stage == .needsAgents(org("acme")))
        portal.setAgents(.success([agent("a1"), agent("a2")]), for: "acme")
        let again = await run(portal, from: result.selection)
        #expect(again.problem == nil)
        #expect(again.selection.stage == .chooseAgent(org("acme")))
        #expect(portal.calls == ["organizations", "agents:acme", "agents:acme"], "Retry skips what is loaded")
    }
}
