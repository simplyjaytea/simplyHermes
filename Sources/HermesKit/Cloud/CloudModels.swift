import Foundation

/// Names shared by the Hermes Cloud flow (WP-17).
public enum HermesCloud {
    /// The sign-in provider. The public desktop guide names none for Hermes Cloud, so `nous` is an assumption from
    /// the plan; this repo knows it only as a login provider of a gateway.
    public static let provider = "nous"
    /// What lists call a saved Hermes Cloud connection.
    public static let displayName = "Hermes Cloud"
}

/// An organization a Hermes Cloud login belongs to.
public struct CloudOrganization: Sendable, Hashable, Identifiable {
    /// Stable id from the portal.
    public var id: String
    /// Name for lists.
    public var name: String

    /// Creates an organization.
    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// A hosted Hermes agent a login can reach: a gateway the app connects to like any remote one.
public struct CloudAgent: Sendable, Hashable, Identifiable {
    /// What the portal says the agent is doing. Only used to caption a row; it never blocks Connect.
    public enum Status: Sendable, Hashable {
        case running
        case starting
        case stopped
        /// Empty or not recognised.
        case unknown

        /// Reads the portal's word for it, case-insensitively. No source documents the words, so the lists below are
        /// guesses and anything else reads as unknown.
        public init(portalValue: String?) {
            switch portalValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "running", "ready", "online", "active", "started": self = .running
            case "starting", "provisioning", "pending", "creating", "booting", "deploying", "restarting":
                self = .starting
            case "stopped", "stopping", "paused", "suspended", "offline", "inactive": self = .stopped
            default: self = .unknown
            }
        }

        /// Short caption for a row, nil when the status is not known.
        public var caption: String? {
            switch self {
            case .running: "Running"
            case .starting: "Starting"
            case .stopped: "Stopped"
            case .unknown: nil
            }
        }
    }

    /// Stable id from the portal. Together with the organization id it identifies the agent.
    public var id: String
    /// Name for lists.
    public var name: String
    /// What the portal says it is doing.
    public var status: Status
    /// Where the agent's gateway answers. Plain HTTP to a public host never gets here (plan Q14).
    public var endpoint: HermesEndpoint

    /// Creates an agent.
    public init(id: String, name: String, status: Status = .unknown, endpoint: HermesEndpoint) {
        self.id = id
        self.name = name
        self.status = status
        self.endpoint = endpoint
    }
}

/// Where a saved gateway came from when it was found through Hermes Cloud instead of typed. Stored on
/// ``GatewaySettings/cloud``; it holds names and ids only, never a secret.
public struct CloudOrigin: Sendable, Hashable, Codable {
    /// The organization's portal id.
    public var organizationID: String
    /// The organization's name when the entry was added, for list rows.
    public var organizationName: String
    /// The agent's portal id.
    public var agentID: String
    /// The agent's name when the entry was added, for list rows.
    public var agentName: String

    /// Creates an origin.
    public init(organizationID: String, organizationName: String, agentID: String, agentName: String) {
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.agentID = agentID
        self.agentName = agentName
    }

    /// The origin of `agent` in `organization`.
    public init(organization: CloudOrganization, agent: CloudAgent) {
        self.init(
            organizationID: organization.id, organizationName: organization.name, agentID: agent.id,
            agentName: agent.name)
    }

    /// Two entries with the same key are the same cloud agent: organization id plus agent id (WP-17). Ids are
    /// opaque, so they are compared as written apart from surrounding spaces.
    public var dedupeKey: String {
        let organization = organizationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let agent = agentID.trimmingCharacters(in: .whitespacesAndNewlines)
        return "cloud \(organization)/\(agent)"
    }

    /// One line for list rows: `Hermes Cloud · Acme · research-bot`.
    public var summary: String {
        "\(HermesCloud.displayName) · \(organizationName) · \(agentName)"
    }
}
