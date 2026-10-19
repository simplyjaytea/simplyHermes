import Foundation

extension ServerConnection {
    /// The Hermes Cloud origin of this connection. Nil for gateways the user typed and for SSH servers.
    public var cloudOrigin: CloudOrigin? {
        if case .gateway(let settings) = kind { return settings.cloud }
        return nil
    }

    /// True for a connection found through Hermes Cloud.
    public var isCloud: Bool { cloudOrigin != nil }

    /// The connection for a Hermes Cloud agent (WP-17). It connects like any remote gateway, signing in with the
    /// portal's provider.
    ///
    /// When `saved` already has this agent (same organization id and agent id), the result keeps that entry's id,
    /// name, Face ID choice and date, so saving it refreshes the entry instead of adding a second one. Otherwise the
    /// name is the agent's, made unique among the saved names.
    public static func cloud(
        organization: CloudOrganization, agent: CloudAgent, saved: SavedConnections, now: Date = Date()
    ) -> ServerConnection {
        let origin = CloudOrigin(organization: organization, agent: agent)
        let existing = saved.cloudConnection(for: origin)
        let id = existing?.id ?? UUID()
        let baseName = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = GatewaySettings(
            endpoint: agent.endpoint, signIn: .browser(provider: HermesCloud.provider), cloud: origin)
        return ServerConnection(
            id: id,
            name: existing?.name ?? saved.uniqueName(baseName.isEmpty ? HermesCloud.displayName : baseName, for: id),
            kind: .gateway(settings), requiresUnlock: existing?.requiresUnlock, createdAt: existing?.createdAt ?? now)
    }
}

extension SavedConnections {
    /// The saved connection for the same cloud agent: the same organization id and agent id.
    public func cloudConnection(for origin: CloudOrigin) -> ServerConnection? {
        let key = origin.dedupeKey
        return connections.first { $0.cloudOrigin?.dedupeKey == key }
    }

    /// True when the agent is saved already.
    public func contains(agent: CloudAgent, in organization: CloudOrganization) -> Bool {
        cloudConnection(for: CloudOrigin(organization: organization, agent: agent)) != nil
    }
}
