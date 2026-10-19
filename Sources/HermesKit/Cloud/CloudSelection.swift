import Foundation

/// Which organization and agent the user is picking, as a pure value (WP-17).
///
/// The rules:
/// - One organization is chosen on its own. Several wait for a pick.
/// - The agents of the chosen organization are listed once each. One agent is preselected, but nothing connects
///   until the user taps Connect.
/// - An answer for an organization that is no longer the chosen one is dropped.
public struct CloudSelection: Sendable, Equatable {
    /// Where the pick stands. The screens follow it.
    public enum Stage: Sendable, Equatable {
        /// Nothing loaded yet.
        case needsOrganizations
        /// The login belongs to no organization.
        case noOrganizations
        /// Several organizations and none chosen.
        case chooseOrganization
        /// An organization is chosen and its agents are not loaded.
        case needsAgents(CloudOrganization)
        /// The chosen organization has no agents.
        case noAgents(CloudOrganization)
        /// Agents are listed and none is chosen.
        case chooseAgent(CloudOrganization)
        /// An agent is chosen. Connect is allowed.
        case ready(CloudOrganization, CloudAgent)
    }

    /// The organizations of the login, once each, in the portal's order.
    public private(set) var organizations: [CloudOrganization] = []
    /// The agents of the chosen organization, once each, in the portal's order.
    public private(set) var agents: [CloudAgent] = []
    /// The chosen organization's id.
    public private(set) var organizationID: String?
    /// The chosen agent's id.
    public private(set) var agentID: String?
    private var organizationsLoaded = false
    private var agentsLoadedFor: String?

    /// An empty selection: nothing loaded.
    public init() {}

    /// The chosen organization.
    public var organization: CloudOrganization? {
        organizations.first { $0.id == organizationID }
    }

    /// The chosen agent.
    public var agent: CloudAgent? {
        agents.first { $0.id == agentID }
    }

    /// True when the login belongs to several organizations, so the screens offer "Change organization".
    public var canChangeOrganization: Bool { organizations.count > 1 }

    /// Where the pick stands now.
    public var stage: Stage {
        guard organizationsLoaded else { return .needsOrganizations }
        if organizations.isEmpty { return .noOrganizations }
        guard let organization else { return .chooseOrganization }
        guard agentsLoadedFor == organization.id else { return .needsAgents(organization) }
        if agents.isEmpty { return .noAgents(organization) }
        if let agent { return .ready(organization, agent) }
        return .chooseAgent(organization)
    }

    // MARK: - Loading

    /// Takes the organizations the portal listed. Keeps the chosen one when it is still listed; chooses the only one
    /// when there is exactly one. Returns the organization that was chosen and is no longer listed (revoked), if any;
    /// then nothing is chosen, even when one organization is left, because the user confirms it.
    @discardableResult
    public mutating func setOrganizations(_ list: [CloudOrganization]) -> CloudOrganization? {
        let previous = organization
        organizations = Self.unique(list)
        organizationsLoaded = true
        var vanished: CloudOrganization?
        if let organizationID, !organizations.contains(where: { $0.id == organizationID }) {
            vanished = previous
            clearOrganization()
        }
        if organizationID == nil, vanished == nil, organizations.count == 1 {
            chooseOrganization(id: organizations[0].id)
        }
        return vanished
    }

    /// Takes the agents the portal listed for `organizationID`. Drops the answer (false) when another organization
    /// is chosen by now. Keeps the chosen agent when it is still listed; preselects the only one.
    @discardableResult
    public mutating func setAgents(_ list: [CloudAgent], forOrganization organizationID: String) -> Bool {
        guard self.organizationID == organizationID else { return false }
        agents = Self.unique(list)
        agentsLoadedFor = organizationID
        if let agentID, !agents.contains(where: { $0.id == agentID }) { self.agentID = nil }
        if agentID == nil, agents.count == 1 { agentID = agents[0].id }
        return true
    }

    /// Marks everything as stale so the next load asks the portal again. The choices stay while they are still valid.
    public mutating func refresh() {
        organizationsLoaded = false
        agentsLoadedFor = nil
    }

    // MARK: - Choosing

    /// Chooses a listed organization. Returns false for an unknown id. Changing the organization drops the agents.
    @discardableResult
    public mutating func chooseOrganization(id: String) -> Bool {
        guard organizations.contains(where: { $0.id == id }) else { return false }
        if organizationID != id {
            agents = []
            agentID = nil
            agentsLoadedFor = nil
        }
        organizationID = id
        return true
    }

    /// Goes back to the organization list: the choice and its agents are dropped.
    public mutating func clearOrganization() {
        organizationID = nil
        agents = []
        agentID = nil
        agentsLoadedFor = nil
    }

    /// Chooses a listed agent. Returns false for an unknown id.
    @discardableResult
    public mutating func chooseAgent(id: String) -> Bool {
        guard agents.contains(where: { $0.id == id }) else { return false }
        agentID = id
        return true
    }

    /// Forgets an organization the portal refused (access revoked). Nothing is chosen afterwards, even when one
    /// organization is left: the user confirms it.
    public mutating func removeOrganization(id: String) {
        organizations.removeAll { $0.id == id }
        if organizationID == id { clearOrganization() }
    }

    private static func unique<Item: Identifiable>(_ items: [Item]) -> [Item] where Item.ID == String {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
