#if canImport(UIKit)
    import HermesKit

    /// Sample organizations, agents and selections for previews and the model's tests.
    enum CloudSamples {
        static let organizations = [
            CloudOrganization(id: "org_acme", name: "Acme Research"),
            CloudOrganization(id: "org_home", name: "Home lab"),
        ]

        static let agents: [CloudAgent] = [
            sampleAgent("agt_research", "research-bot", .running, "https://research-bot.acme.example"),
            sampleAgent("agt_night", "Night shift", .stopped, "https://night-shift.acme.example"),
            sampleAgent("agt_new", "Draft writer", .starting, "https://draft-writer.acme.example"),
        ]

        /// Two organizations listed and none chosen.
        static var severalOrganizations: CloudSelection {
            var selection = CloudSelection()
            selection.setOrganizations(organizations)
            return selection
        }

        /// One organization chosen and its agents listed, none picked.
        static var agentsToChoose: CloudSelection {
            var selection = CloudSelection()
            selection.setOrganizations(Array(organizations.prefix(1)))
            selection.setAgents(agents, forOrganization: organizations[0].id)
            return selection
        }

        private static func sampleAgent(
            _ id: String, _ name: String, _ status: CloudAgent.Status, _ address: String
        ) -> CloudAgent {
            guard let endpoint = HermesEndpoint(string: address) else {
                preconditionFailure("A sample address is valid")
            }
            return CloudAgent(id: id, name: name, status: status, endpoint: endpoint)
        }
    }

    /// A portal that answers at once with the samples. For previews.
    struct PreviewCloudPortal: CloudPortalClient {
        var endpoint: HermesEndpoint { NousPortalClient.portalEndpoint }

        func organizations(accessToken: String) async throws -> [CloudOrganization] {
            CloudSamples.organizations
        }

        func agents(in organization: CloudOrganization, accessToken: String) async throws -> [CloudAgent] {
            CloudSamples.agents
        }
    }
#endif
