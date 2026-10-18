import Foundation

/// What one run of ``CloudDiscovery`` found.
public struct CloudDiscoveryResult: Sendable, Equatable {
    /// The selection after the run.
    public var selection: CloudSelection
    /// Why the run stopped short, or nil when the user has something to pick (or an agent is ready).
    public var problem: CloudProblem?

    /// Creates a result.
    public init(selection: CloudSelection, problem: CloudProblem? = nil) {
        self.selection = selection
        self.problem = problem
    }
}

/// Walks the discovery steps that need no choice from the user (WP-17): list the organizations, take the only one,
/// list its agents. It stops where the user must pick, or where something is wrong.
public struct CloudDiscovery: Sendable {
    /// The portal to ask.
    public let portal: any CloudPortalClient

    /// Creates the walker.
    public init(portal: any CloudPortalClient) {
        self.portal = portal
    }

    /// Runs from where `selection` stands. Pure apart from the portal calls; the caller keeps the returned selection.
    public func advance(_ selection: CloudSelection, accessToken: String) async -> CloudDiscoveryResult {
        var next = selection
        do {
            if case .needsOrganizations = next.stage {
                let listed = try await portal.organizations(accessToken: accessToken)
                if let revoked = next.setOrganizations(listed) {
                    return CloudDiscoveryResult(
                        selection: next, problem: .organizationRevoked(organization: revoked.name))
                }
            }
            if case .needsAgents(let organization) = next.stage {
                do {
                    let listed = try await portal.agents(in: organization, accessToken: accessToken)
                    next.setAgents(listed, forOrganization: organization.id)
                } catch CloudPortalError.organizationRevoked(let revoked) {
                    next.removeOrganization(id: revoked.id)
                    return CloudDiscoveryResult(
                        selection: next, problem: .organizationRevoked(organization: revoked.name))
                }
            }
        } catch {
            return CloudDiscoveryResult(selection: next, problem: CloudProblem(portalError: error))
        }
        switch next.stage {
        case .noOrganizations:
            return CloudDiscoveryResult(selection: next, problem: .noOrganizations)
        case .noAgents(let organization):
            return CloudDiscoveryResult(selection: next, problem: .noAgents(organization: organization.name))
        case .needsOrganizations, .chooseOrganization, .needsAgents, .chooseAgent, .ready:
            return CloudDiscoveryResult(selection: next)
        }
    }
}
