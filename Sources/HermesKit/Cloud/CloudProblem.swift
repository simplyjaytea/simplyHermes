import Foundation

/// What went wrong in the Hermes Cloud flow, in words the user can act on (WP-17). Every case has a primary action,
/// and none of them ends the flow: the user can retry, sign in again or cancel.
public enum CloudProblem: Error, Sendable, Equatable {
    /// The portal does not know the sign-in (none yet, expired or refused).
    case notSignedIn
    /// The browser sign-in did not finish. `detail` may be empty.
    case signInFailed(String)
    /// No answer from the portal, or it had a problem.
    case portalUnreachable(String)
    /// The portal asked the app to slow down.
    case portalBusy
    /// The portal answered in a shape this version of the app cannot read.
    case unexpectedReply(String)
    /// The login belongs to no organization.
    case noOrganizations
    /// The organization has no agents.
    case noAgents(organization: String)
    /// The login lost access to the organization.
    case organizationRevoked(organization: String)
    /// The agent's gateway did not accept the sign-in.
    case agentSignInRejected(agent: String)
    /// The agent runs a Hermes older than this app supports. Hermes Cloud updates its agents itself.
    case agentTooOld(agent: String, found: String)
    /// The agent's gateway did not answer, or answered wrongly.
    case agentUnreachable(agent: String, detail: String)
    /// Anything else that stopped the connection.
    case connectionFailed(String)

    /// What the primary button does.
    public enum Action: Sendable, Equatable {
        /// Run the browser sign-in to Hermes Cloud again.
        case signIn
        /// Run the browser sign-in to the chosen agent itself, then connect.
        case signInToAgent
        /// Run the step that failed again.
        case retry
        /// Ask the portal again from the top.
        case checkAgain
        /// Go back to the organization list.
        case chooseOrganization
    }

    /// What the primary button does.
    public var action: Action {
        switch self {
        case .notSignedIn, .signInFailed: .signIn
        case .agentSignInRejected: .signInToAgent
        case .noOrganizations, .noAgents: .checkAgain
        case .organizationRevoked: .chooseOrganization
        case .portalUnreachable, .portalBusy, .unexpectedReply, .agentTooOld, .agentUnreachable, .connectionFailed:
            .retry
        }
    }

    /// The primary button's title.
    public var actionTitle: String {
        if case .agentSignInRejected(let agent) = self { return "Sign in to \(agent)" }
        switch action {
        case .signIn: return self == .notSignedIn ? "Sign in" : "Sign in again"
        case .signInToAgent: return "Sign in to the agent"
        case .retry: return "Try again"
        case .checkAgain: return "Check again"
        case .chooseOrganization: return "Choose another organization"
        }
    }

    /// True when the problem is about the chosen agent, so the screen can offer a way back to the agent list.
    public var concernsAgent: Bool {
        switch self {
        case .agentSignInRejected, .agentTooOld, .agentUnreachable, .connectionFailed: true
        default: false
        }
    }

    /// SF Symbol for the problem screen.
    public var systemImage: String {
        switch self {
        case .notSignedIn, .signInFailed, .agentSignInRejected: "person.crop.circle.badge.exclamationmark"
        case .portalUnreachable, .portalBusy, .agentUnreachable: "wifi.exclamationmark"
        case .noOrganizations, .noAgents: "tray"
        case .organizationRevoked: "lock"
        case .unexpectedReply, .agentTooOld, .connectionFailed: "exclamationmark.triangle"
        }
    }

    /// A short heading.
    public var title: String {
        switch self {
        case .notSignedIn: "Sign in to Hermes Cloud"
        case .signInFailed: "Sign-in didn't finish"
        case .portalUnreachable: "Can't reach Hermes Cloud"
        case .portalBusy: "Hermes Cloud is busy"
        case .unexpectedReply: "Hermes Cloud sent a reply this app can't read"
        case .noOrganizations: "No organization yet"
        case .noAgents(let organization): "No agents in \(organization)"
        case .organizationRevoked(let organization): "You no longer have access to \(organization)"
        case .agentSignInRejected(let agent): "\(agent) didn't accept the sign-in"
        case .agentTooOld(let agent, _): "\(agent) needs an update"
        case .agentUnreachable(let agent, _): "Can't reach \(agent)"
        case .connectionFailed: "Couldn't connect"
        }
    }

    /// One or two calm sentences.
    public var message: String {
        switch self {
        case .notSignedIn:
            "Sign in with your Nous account to see your agents."
        case .signInFailed(let detail):
            "Hermes Cloud didn't accept the sign-in. Try again." + Self.suffix(detail)
        case .portalUnreachable(let detail):
            "Check your connection and try again." + Self.suffix(detail)
        case .portalBusy:
            "Wait a minute, then try again."
        case .unexpectedReply(let detail):
            "This version of simplyHermes may be out of step with Hermes Cloud. Try again later." + Self.suffix(detail)
        case .noOrganizations:
            "This account isn't in a Hermes Cloud organization yet. Create or join one in the Nous Portal, then check again."
        case .noAgents:
            "Create an agent in the Nous Portal, then check again."
        case .organizationRevoked:
            "An admin may have removed you from it. Choose another organization, or ask them to add you back."
        case .agentSignInRejected:
            "The agent asked for its own sign-in. Sign in to it with your Nous account, then it connects."
        case .agentTooOld(_, let found):
            "This agent runs an older Hermes than simplyHermes supports. Hermes Cloud updates its agents itself, so try "
                + "again later." + Self.suffix(found)
        case .agentUnreachable(_, let detail):
            "The agent may be stopped or still starting. Check it in the Nous Portal, then try again."
                + Self.suffix(detail)
        case .connectionFailed(let message):
            message
        }
    }

    private static func suffix(_ detail: String) -> String {
        detail.isEmpty ? "" : " (\(detail))"
    }
}

extension CloudProblem {
    /// A portal failure as a problem. Anything that is not a ``CloudPortalError`` counts as unreachable.
    public init(portalError error: any Error) {
        switch error {
        case CloudPortalError.notSignedIn:
            self = .notSignedIn
        case CloudPortalError.organizationRevoked(let organization):
            self = .organizationRevoked(organization: organization.name)
        case CloudPortalError.unreachable(let detail):
            self = .portalUnreachable(detail)
        case CloudPortalError.busy:
            self = .portalBusy
        case CloudPortalError.unexpectedReply(let detail):
            self = .unexpectedReply(detail)
        default:
            self = .portalUnreachable("\(error)")
        }
    }

    /// A failed browser sign-in as a problem. Nil when the user closed the sheet: that is no problem.
    public init?(signInError error: any Error) {
        switch error {
        case NativeSignInError.cancelled, is CancellationError:
            return nil
        case NativeSignInError.server(let detail):
            self = .signInFailed(detail)
        case NativeSignInError.codeRejected, NativeSignInError.stateMismatch, NativeSignInError.missingCode,
            NativeSignInError.sessionExpired:
            self = .signInFailed("")
        case RESTError.transport(let detail):
            self = .portalUnreachable(detail)
        default:
            self = .signInFailed(error.localizedDescription)
        }
    }

    /// A failed browser sign-in to the agent itself as a problem. Closing the sheet returns to the sign-in offer.
    public init(agentSignInError error: any Error, agent: String) {
        switch error {
        case RESTError.transport(let detail):
            self = .agentUnreachable(agent: agent, detail: detail)
        default:
            self = .agentSignInRejected(agent: agent)
        }
    }

    /// A failed connection test of the agent's gateway as a problem. The test's own wording talks about typed
    /// addresses and `hermes update`, which do not apply to a cloud agent.
    public init(testFailure failure: ConnectionTestFailure, agent: String) {
        switch failure {
        case .unreachable(let detail):
            self = .agentUnreachable(agent: agent, detail: detail)
        case .server(let status, _):
            self = .agentUnreachable(agent: agent, detail: "it answered \(status)")
        case .webSocket(let detail):
            self = .agentUnreachable(agent: agent, detail: "the live connection failed: \(detail)")
        case .notHermes:
            self = .agentUnreachable(agent: agent, detail: "its address answered, but not as Hermes")
        case .signInRequired, .wrongCredentials, .missingSecret:
            self = .agentSignInRejected(agent: agent)
        case .serverTooOld(let found):
            self = .agentTooOld(agent: agent, found: found)
        case .rateLimited:
            self = .connectionFailed("Too many attempts. Try again in a minute.")
        case .hostKeyRejected, .hostKeyChanged, .ssh, .invalidForm:
            self = .connectionFailed(failure.message)
        }
    }
}
