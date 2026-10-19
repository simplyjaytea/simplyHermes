import Foundation

/// The Nous Portal as a ``CloudPortalClient`` (WP-17). UNTESTED LIVE. Every portal detail below is an assumption.
///
/// What the sources document about listing organizations and agents, and what they do not:
///
/// This repo documents no way to list them:
/// - `docs/protocol.md` does not mention the portal or Hermes Cloud. It names `nous` (OAuth) only as a login provider
///   of a gateway, and its section 12 says native PKCE with `nous` is untested.
/// - `GET /api/portal` (`dashboard-openapi.json`) is a gateway's own Portal login status. It has no response schema,
///   it needs a gateway that is already reachable, and a Hermes Cloud entry has no address yet at that point.
/// - `portal_url` in the billing and free-tier results (`gateway-contract.openrpc.json`) is a link to the portal's
///   web pages.
/// - `GET /api/auth/me` and `subscription.state` give one `org_id` / `org_name` for a session on a gateway that is
///   already connected. They do not list organizations.
/// - `agents.list` lists background processes on a gateway, not hosted agents.
///
/// The public desktop guide, https://hermes-agent.nousresearch.com/docs/user-guide/desktop, documents the flow and
/// nothing beneath it. Hermes Cloud is one of four kinds in the Add flow. The user signs in once to Hermes Cloud and
/// picks from the agents on the account, with no URL to paste. An organization picker appears when the account spans
/// several organizations. Cloud entries come from that sign-in and discovery, never from a typed URL, and the
/// platform updates them. The guide names no endpoint, no API route, no URL format and no sign-in provider.
///
/// The public guide, https://hermes-agent.nousresearch.com/docs/guides/manage-hermes-cloud-with-mcp, documents how
/// Hermes manages Hermes Cloud through an MCP server at `https://portal.nousresearch.com/mcp`. It documents OAuth
/// with PKCE, OAuth endpoints found through RFC 9728 and RFC 8414 metadata, client registration through RFC 7591
/// Dynamic Client Registration, and the organization being chosen once in the browser during authorization. It
/// documents two tools by name: `agents` (list, get or status, cost estimate) and `agent` (start, stop, restart,
/// create, destroy, update environment, update image). It points to two Portal web pages where the user sees the
/// same hosted instances: https://portal.nousresearch.com/cloud and `/agents`. It documents no REST route, no JSON
/// response shape or field name, no status word, no HTTP status code, no tool arguments, no tool result schema, and
/// no instance address, URL, hostname or dashboard. It does not mention the `/auth/native/*` routes that the app's
/// browser sign-in (WP-13) calls.
///
/// Everything else here is assumed, guessed and unverified against a real portal:
/// - Assumed: the portal origin is `https://portal.nousresearch.com` (the MCP URL's host) and it also serves REST.
/// - Assumed: it accepts the app's native PKCE sign-in with provider `nous`, and those tokens work as a bearer token.
/// - Assumed: `GET /api/organizations` returns `{"organizations": [{"id", "name"}]}`. A bare array is accepted too.
/// - Assumed: `GET /api/organizations/{id}/agents` returns `{"agents": [{"id", "name", "status", "url"}]}`. The
///   agent's address may also sit under the guessed names `gateway_url`, `dashboard_url`, `endpoint` or `hostname`.
/// - Assumed: each listed agent carries an HTTPS address of a gateway the app can reach like any remote gateway.
/// - Assumed: `403` or `410` on the agents route means the login lost access to the organization.
///
/// Every route, key and status word is in ``Route``, in the private wire types at the end of this file, or in
/// ``CloudAgent/Status``, so the first live test can correct them in one place. When a guess is wrong the client
/// throws ``CloudPortalError/unexpectedReply(_:)``. It never makes up a list.
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

    /// `https://portal.nousresearch.com`: the host of the MCP server URL in the public guide named in the header.
    /// That this origin also serves a REST API for this app is an assumption.
    public static var portalEndpoint: HermesEndpoint {
        guard let endpoint = HermesEndpoint(string: "https://portal.nousresearch.com") else {
            preconditionFailure("The portal URL is valid")
        }
        return endpoint
    }

    /// The assumed routes. Neither appears in any source named in the header.
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

    /// Maps a REST failure to what the screens say. `organization` is set for the agents route. Assumed and
    /// unverified: there `403` or `410` mean the login lost access to the organization. A `404` is read as a wrong
    /// route, not as a revocation.
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

// MARK: - Wire types (guessed shapes, unverified)

/// A list item the portal is assumed to send, and the guessed keys its list may sit under.
private protocol PortalListItem: Decodable, Sendable {
    static var listKeys: [String] { get }
}

/// A JSON array, or an object with the array under one of the item's guessed keys. The real shape is unknown, so
/// both are accepted.
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

/// An id sent as a string or as a number. The real type is unknown, so both are accepted.
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

/// An organization as the portal is assumed to send it. Every field name is a guess.
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

/// An agent as the portal is assumed to send it. Every field name, and which one holds the address, is a guess.
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
