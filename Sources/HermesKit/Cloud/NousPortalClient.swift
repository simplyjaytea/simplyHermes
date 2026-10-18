import Foundation

/// The Nous Portal as a ``CloudPortalClient`` (WP-17). UNTESTED LIVE, AND A GUESS.
///
/// Nothing in this repo, and nothing in the public desktop docs, says how to list organizations or agents:
/// - `GET /api/portal` (`dashboard-openapi.json`) is a gateway's own Portal login status. It has no response schema,
///   it needs a gateway that is already reachable, and a Hermes Cloud entry has no address yet at that point.
/// - `portal_url` in the billing and free-tier results is a link to the portal's web pages.
/// - `GET /api/auth/me` and `subscription.state` give one `org_id` / `org_name` for a session on a gateway that is
///   already connected. They do not list organizations.
/// - `agents.list` (`gateway-contract.openrpc.json`) lists background processes on a gateway, not hosted agents.
/// - The desktop docs say only: sign in once, pick an organization if the login has several, pick an agent, no URL.
///
/// The public guide "Manage Hermes Cloud with MCP" names the host `portal.nousresearch.com` and a portal MCP server
/// with an `agents` tool, and says the organization is chosen in the browser while signing in. That server needs
/// its own OAuth client registration, so the app's browser sign-in (WP-13) cannot reach it, and its tool arguments
/// and replies are not documented.
///
/// So this client assumes plain REST on the portal origin, with the bearer token the browser sign-in returned:
/// - `GET /api/organizations` answers `{"organizations": [{"id", "name"}]}` (a bare array is accepted too).
/// - `GET /api/organizations/{id}/agents` answers `{"agents": [{"id", "name", "status", "url"}]}`. The agent's
///   address may also come as `gateway_url`, `dashboard_url`, `endpoint` or `hostname`.
/// - `403` on the agents route means the login lost access to the organization.
///
/// Every name above is in ``Route`` and in the private wire types at the end of this file, so the first live test
/// can fix them in one place. A wrong guess ends in ``CloudPortalError/unexpectedReply(_:)``, never in a made-up
/// list.
public struct NousPortalClient: CloudPortalClient {
    public let endpoint: HermesEndpoint
    private let makeTransport: @Sendable () -> any HTTPTransport

    /// Creates a client. `makeTransport` gives each call a fresh transport.
    public init(
        endpoint: HermesEndpoint = Self.portalEndpoint,
        makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionHTTPTransport(timeout: 20) }
    ) {
        self.endpoint = endpoint
        self.makeTransport = makeTransport
    }

    /// `https://portal.nousresearch.com`, the host the public docs name for the Nous Portal.
    public static var portalEndpoint: HermesEndpoint {
        guard let endpoint = HermesEndpoint(string: "https://portal.nousresearch.com") else {
            preconditionFailure("The portal URL is valid")
        }
        return endpoint
    }

    /// The guessed routes.
    enum Route {
        static let organizations = "/api/organizations"

        static func agents(in organization: CloudOrganization) -> String {
            "/api/organizations/\(organization.id)/agents"
        }
    }

    public func organizations(accessToken: String) async throws -> [CloudOrganization] {
        let wire: PortalList<OrganizationWire>
        do {
            wire = try await client(accessToken).get(Route.organizations, scoped: false)
        } catch {
            throw Self.portalError(error, organization: nil)
        }
        let organizations = wire.items.compactMap(\.organization)
        if !wire.items.isEmpty, organizations.isEmpty {
            throw CloudPortalError.unexpectedReply("none of the \(wire.items.count) organizations had an id")
        }
        return organizations
    }

    public func agents(in organization: CloudOrganization, accessToken: String) async throws -> [CloudAgent] {
        let wire: PortalList<AgentWire>
        do {
            wire = try await client(accessToken).get(Route.agents(in: organization), scoped: false)
        } catch {
            throw Self.portalError(error, organization: organization)
        }
        let agents = wire.items.compactMap { $0.agent() }
        if !wire.items.isEmpty, agents.isEmpty {
            throw CloudPortalError.unexpectedReply("none of the \(wire.items.count) agents had an HTTPS address")
        }
        return agents
    }

    private func client(_ accessToken: String) -> RESTClient {
        var config = RESTClientConfig()
        config.maxRateLimitRetries = 0
        return RESTClient(endpoint: endpoint, transport: makeTransport(), auth: .bearer(accessToken), config: config)
    }

    /// Maps a REST failure to what the screens say. `organization` is set for the agents route, where `403` means
    /// the access was revoked. Only `403` and `410` do: a `404` there more likely means a wrong route.
    static func portalError(_ error: any Error, organization: CloudOrganization?) -> any Error {
        switch error {
        case is CancellationError, is CloudPortalError:
            return error
        case RESTError.unauthorized:
            return CloudPortalError.notSignedIn
        case RESTError.rateLimited(let retryAfter):
            return CloudPortalError.busy(retryAfter: retryAfter)
        case RESTError.http(let status, let detail):
            switch (status, organization) {
            case (403, let organization?), (410, let organization?):
                return CloudPortalError.organizationRevoked(organization)
            case (401, _), (403, nil):
                return CloudPortalError.notSignedIn
            case (429, _):
                return CloudPortalError.busy(retryAfter: nil)
            case (500..., _):
                return CloudPortalError.unreachable("Hermes Cloud answered \(status)")
            default:
                return CloudPortalError.unexpectedReply("status \(status)" + (detail.map { ": \($0)" } ?? ""))
            }
        case RESTError.transport(let detail):
            return CloudPortalError.unreachable(detail)
        case RESTError.unexpectedContent(let contentType):
            return CloudPortalError.unexpectedReply("not JSON (\(contentType ?? "unknown type"))")
        case RESTError.decoding(let detail):
            return CloudPortalError.unexpectedReply(detail)
        default:
            return CloudPortalError.unreachable("\(error)")
        }
    }
}

// MARK: - Wire types (the guessed shapes)

/// A list item the portal sends, and the keys its list may sit under.
private protocol PortalListItem: Decodable, Sendable {
    static var listKeys: [String] { get }
}

/// A JSON array, or an object with the array under one of the item's keys.
private struct PortalList<Item: PortalListItem>: Decodable, Sendable {
    var items: [Item]

    init(from decoder: any Decoder) throws {
        if let array = try? decoder.singleValueContainer().decode([Item].self) {
            items = array
            return
        }
        let container = try decoder.container(keyedBy: PortalKey.self)
        for name in Item.listKeys {
            if let key = PortalKey(stringValue: name), container.contains(key) {
                items = try container.decode([Item].self, forKey: key)
                return
            }
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "no list under \(Item.listKeys.joined(separator: ", "))"))
    }
}

private struct PortalKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// An id sent as a string or as a number.
private struct PortalID: Decodable, Sendable {
    let value: String

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let number = try? container.decode(Int.self) {
            value = String(number)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "id is not a string or number"))
        }
    }

    /// The id as a single path segment, or nil when it is empty or could change the route.
    var segment: String? {
        value.isEmpty || value.contains("/") || value.contains("\\") ? nil : value
    }
}

private func firstText(_ candidates: String?...) -> String? {
    candidates.lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
}

private struct OrganizationWire: PortalListItem {
    static let listKeys = ["organizations", "orgs", "items", "data"]

    var id: PortalID?
    var name: String?
    var displayName: String?
    var slug: String?

    var organization: CloudOrganization? {
        guard let id = id?.segment else { return nil }
        return CloudOrganization(id: id, name: firstText(displayName, name, slug) ?? id)
    }
}

private struct AgentWire: PortalListItem {
    static let listKeys = ["agents", "instances", "items", "data"]

    var id: PortalID?
    var name: String?
    var displayName: String?
    var status: String?
    var gatewayUrl: String?
    var dashboardUrl: String?
    var url: String?
    var endpoint: String?
    var hostname: String?

    /// Nil without an id or without an HTTPS address: the app sends the sign-in tokens to that address, so plain
    /// HTTP is never accepted for a cloud agent.
    func agent() -> CloudAgent? {
        guard let id = id?.segment,
            let address = firstText(gatewayUrl, dashboardUrl, url, endpoint, hostname),
            case .success(let parsed) = ConnectionAddress.parse(address),
            parsed.endpoint.baseURL.scheme?.lowercased() == "https"
        else { return nil }
        return CloudAgent(
            id: id, name: firstText(displayName, name) ?? id, status: CloudAgent.Status(portalValue: status),
            endpoint: parsed.endpoint)
    }
}
