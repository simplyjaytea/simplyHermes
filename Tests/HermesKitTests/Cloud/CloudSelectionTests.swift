import Foundation
import HermesKit
import Testing

/// WP-17 CI gate: one organization is picked on its own, several need a pick, agents are listed once, and stale
/// answers are dropped.
@Suite struct CloudSelectionTests {
    @Test func startsWithNothingLoaded() {
        let selection = CloudSelection()
        #expect(selection.stage == .needsOrganizations)
        #expect(selection.organization == nil && selection.agent == nil)
        #expect(!selection.canChangeOrganization)
    }

    @Test func theOnlyOrganizationIsPickedAutomatically() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme", "Acme")])
        #expect(selection.organizationID == "acme")
        #expect(selection.stage == .needsAgents(org("acme", "Acme")))
        #expect(!selection.canChangeOrganization)
    }

    @Test func severalOrganizationsNeedAPick() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        #expect(selection.stage == .chooseOrganization)
        #expect(selection.canChangeOrganization)
        let unknown = selection.chooseOrganization(id: "nope")
        #expect(!unknown)
        #expect(selection.stage == .chooseOrganization)
        let chosen = selection.chooseOrganization(id: "home")
        #expect(chosen)
        #expect(selection.stage == .needsAgents(org("home")))
    }

    @Test func noOrganizationsIsItsOwnStage() {
        var selection = CloudSelection()
        selection.setOrganizations([])
        #expect(selection.stage == .noOrganizations)
    }

    @Test func organizationsAreListedOnce() {
        var selection = CloudSelection()
        selection.setOrganizations([org("a", "First"), org("b"), org("a", "Second")])
        #expect(selection.organizations == [org("a", "First"), org("b")])
    }

    @Test func agentsAreListedOnceAndWaitForThePick() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme")])
        selection.setAgents([agent("a1"), agent("a2"), agent("a1", "repeat")], forOrganization: "acme")
        #expect(selection.agents.map(\.id) == ["a1", "a2"])
        #expect(selection.stage == .chooseAgent(org("acme")))
        let chosen = selection.chooseAgent(id: "a2")
        #expect(chosen)
        #expect(selection.stage == .ready(org("acme"), agent("a2")))
        let unknown = selection.chooseAgent(id: "nope")
        #expect(!unknown)
        #expect(selection.agentID == "a2")
    }

    @Test func theOnlyAgentIsPreselectedButStillNeedsConnect() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme")])
        selection.setAgents([agent("only")], forOrganization: "acme")
        #expect(selection.stage == .ready(org("acme"), agent("only")))
    }

    @Test func noAgentsIsItsOwnStage() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme")])
        selection.setAgents([], forOrganization: "acme")
        #expect(selection.stage == .noAgents(org("acme")))
    }

    @Test func aStaleAgentListIsDropped() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        selection.chooseOrganization(id: "acme")
        selection.chooseOrganization(id: "home")
        let kept = selection.setAgents([agent("a1")], forOrganization: "acme")
        #expect(!kept, "The answer was for the old choice")
        #expect(selection.agents.isEmpty)
        #expect(selection.stage == .needsAgents(org("home")))
    }

    @Test func changingTheOrganizationDropsItsAgents() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        selection.chooseOrganization(id: "acme")
        selection.setAgents([agent("a1"), agent("a2")], forOrganization: "acme")
        selection.chooseAgent(id: "a1")
        selection.chooseOrganization(id: "acme")
        #expect(selection.agentID == "a1", "Choosing the same organization again changes nothing")
        selection.chooseOrganization(id: "home")
        #expect(selection.agents.isEmpty && selection.agentID == nil)
        selection.clearOrganization()
        #expect(selection.stage == .chooseOrganization)
    }

    @Test func refreshKeepsValidChoices() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        selection.chooseOrganization(id: "acme")
        selection.setAgents([agent("a1"), agent("a2")], forOrganization: "acme")
        selection.chooseAgent(id: "a2")
        selection.refresh()
        #expect(selection.stage == .needsOrganizations)
        let gone = selection.setOrganizations([org("acme"), org("home")])
        #expect(gone == nil)
        #expect(selection.stage == .needsAgents(org("acme")))
        selection.setAgents([agent("a2"), agent("a3")], forOrganization: "acme")
        #expect(selection.stage == .ready(org("acme"), agent("a2")), "The agent is still there, so it stays chosen")
    }

    @Test func aChosenAgentThatDisappearsIsDropped() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme")])
        selection.setAgents([agent("a1"), agent("a2")], forOrganization: "acme")
        selection.chooseAgent(id: "a1")
        selection.refresh()
        selection.setOrganizations([org("acme")])
        selection.setAgents([agent("a2"), agent("a3")], forOrganization: "acme")
        #expect(selection.agentID == nil)
        #expect(selection.stage == .chooseAgent(org("acme")))
    }

    @Test func aChosenOrganizationThatDisappearsIsReportedAndNotReplaced() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        selection.chooseOrganization(id: "acme")
        selection.refresh()
        let gone = selection.setOrganizations([org("home")])
        #expect(gone == org("acme"))
        #expect(selection.stage == .chooseOrganization, "The user confirms the one that is left")
        #expect(selection.organizationID == nil)
    }

    @Test func removingARevokedOrganization() {
        var selection = CloudSelection()
        selection.setOrganizations([org("acme"), org("home")])
        selection.chooseOrganization(id: "acme")
        selection.removeOrganization(id: "acme")
        #expect(selection.organizations == [org("home")])
        #expect(selection.stage == .chooseOrganization)
        selection.removeOrganization(id: "home")
        #expect(selection.stage == .noOrganizations)
    }
}
