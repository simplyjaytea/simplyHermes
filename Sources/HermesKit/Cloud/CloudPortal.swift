import Foundation

/// Lists what a Hermes Cloud login can reach (WP-17): its organizations, and the agents of one organization.
///
/// ``NousPortalClient`` is the one live implementation. It is a guess (see its header): no contract in this repo
/// and no public page describes the portal's discovery API. Tests and previews pass a stub.
public protocol CloudPortalClient: Sendable {
    /// The portal's origin. The browser sign-in runs against it.
    var endpoint: HermesEndpoint { get }

    /// The organizations the login belongs to. An empty list is an answer, not an error.
    /// Throws ``CloudPortalError``.
    func organizations(accessToken: String) async throws -> [CloudOrganization]

    /// The agents tied to the login in `organization`. An empty list is an answer, not an error.
    /// Throws ``CloudPortalError``; ``CloudPortalError/organizationRevoked(_:)`` when the login lost access.
    func agents(in organization: CloudOrganization, accessToken: String) async throws -> [CloudAgent]
}

/// Why the portal could not answer.
public enum CloudPortalError: Error, Sendable, Equatable {
    /// The portal does not accept the sign-in: missing, expired or refused. Sign in again.
    case notSignedIn
    /// The login lost access to this organization.
    case organizationRevoked(CloudOrganization)
    /// No answer, or the portal had a problem (`5xx`). `detail` is the system's reason.
    case unreachable(String)
    /// Too many requests. `retryAfter` is the portal's hint in seconds.
    case busy(retryAfter: Double?)
    /// The portal answered, but not in a shape this version of the app can read.
    case unexpectedReply(String)
}
