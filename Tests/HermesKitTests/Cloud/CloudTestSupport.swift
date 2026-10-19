import Foundation
import HermesKit

/// Loads `Fixtures/cloud/<name>.json`. Hand-written to the shape `NousPortalClient` guesses; none of it was
/// recorded from a live portal.
func cloudFixture(_ name: String) throws -> String {
    let url = FixtureFiles.directory.appendingPathComponent("cloud").appendingPathComponent(name + ".json")
    return try String(contentsOf: url, encoding: .utf8)
}

func org(_ id: String, _ name: String = "") -> CloudOrganization {
    CloudOrganization(id: id, name: name.isEmpty ? id.capitalized : name)
}

func agent(_ id: String, _ name: String = "", host: String = "") -> CloudAgent {
    let address = "https://\(host.isEmpty ? id : host).agents.example"
    return CloudAgent(
        id: id, name: name.isEmpty ? id : name, status: .running, endpoint: HermesEndpoint(string: address)!)
}

/// A portal that answers from a script and remembers what it was asked.
final class StubPortal: CloudPortalClient, @unchecked Sendable {
    let endpoint = NousPortalClient.portalEndpoint
    private let lock = NSLock()
    private var organizationsAnswer: Result<[CloudOrganization], CloudPortalError> = .success([])
    private var agentAnswers: [String: Result<[CloudAgent], CloudPortalError>] = [:]
    private var asked: [String] = []

    init(
        organizations: Result<[CloudOrganization], CloudPortalError> = .success([]),
        agents: [String: Result<[CloudAgent], CloudPortalError>] = [:]
    ) {
        organizationsAnswer = organizations
        agentAnswers = agents
    }

    /// What the portal was asked, in order: `organizations`, then `agents:<organization id>`.
    var calls: [String] { lock.withLock { asked } }

    func setOrganizations(_ answer: Result<[CloudOrganization], CloudPortalError>) {
        lock.withLock { organizationsAnswer = answer }
    }

    func setAgents(_ answer: Result<[CloudAgent], CloudPortalError>, for organization: String) {
        lock.withLock { agentAnswers[organization] = answer }
    }

    func organizations(accessToken: String) async throws -> [CloudOrganization] {
        try lock.withLock {
            asked.append("organizations")
            return try organizationsAnswer.get()
        }
    }

    func agents(in organization: CloudOrganization, accessToken: String) async throws -> [CloudAgent] {
        try lock.withLock {
            asked.append("agents:\(organization.id)")
            return try (agentAnswers[organization.id] ?? .success([])).get()
        }
    }
}
