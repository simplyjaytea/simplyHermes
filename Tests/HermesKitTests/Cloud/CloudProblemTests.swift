import Foundation
import HermesKit
import Testing

/// WP-17 CI gate: every problem reads calmly, offers a way forward, and a compatibility failure does not tell the
/// user to run `hermes update` on a server they cannot reach.
@Suite struct CloudProblemTests {
    private let everyProblem: [CloudProblem] = [
        .notSignedIn,
        .signInFailed(""),
        .signInFailed("access_denied"),
        .portalUnreachable("offline"),
        .portalBusy,
        .unexpectedReply("status 404"),
        .noOrganizations,
        .noAgents(organization: "Acme"),
        .organizationRevoked(organization: "Acme"),
        .agentSignInRejected(agent: "bot"),
        .agentTooOld(agent: "bot", found: "release 2026.1.1"),
        .agentUnreachable(agent: "bot", detail: "timed out"),
        .connectionFailed("Too many attempts."),
    ]

    @Test func everyProblemHasWordsAnIconAndAWayForward() {
        for problem in everyProblem {
            #expect(!problem.title.isEmpty && !problem.message.isEmpty, "\(problem)")
            #expect(!problem.actionTitle.isEmpty && !problem.systemImage.isEmpty, "\(problem)")
            let words = (problem.title + " " + problem.message).lowercased()
            #expect(!words.contains("!"), "Calm copy: \(problem)")
            #expect(!words.contains("error") && !words.contains("failed"), "Plain words: \(problem)")
        }
    }

    @Test func actionsFitTheProblem() {
        #expect(CloudProblem.notSignedIn.action == .signIn)
        #expect(CloudProblem.notSignedIn.actionTitle == "Sign in")
        #expect(CloudProblem.signInFailed("").actionTitle == "Sign in again")
        #expect(CloudProblem.agentSignInRejected(agent: "bot").action == .signInToAgent)
        #expect(CloudProblem.agentSignInRejected(agent: "bot").actionTitle == "Sign in to bot")
        #expect(CloudProblem.noOrganizations.action == .checkAgain)
        #expect(CloudProblem.noAgents(organization: "Acme").actionTitle == "Check again")
        #expect(CloudProblem.organizationRevoked(organization: "Acme").action == .chooseOrganization)
        for problem in [
            CloudProblem.portalUnreachable("x"), .portalBusy, .unexpectedReply("x"),
            .agentTooOld(agent: "b", found: "x"), .agentUnreachable(agent: "b", detail: "x"), .connectionFailed("x"),
        ] {
            #expect(problem.action == .retry && problem.actionTitle == "Try again", "\(problem)")
        }
    }

    @Test func onlyAgentProblemsOfferTheWayBackToTheAgentList() {
        let aboutTheAgent = everyProblem.filter(\.concernsAgent)
        #expect(
            aboutTheAgent == [
                .agentSignInRejected(agent: "bot"), .agentTooOld(agent: "bot", found: "release 2026.1.1"),
                .agentUnreachable(agent: "bot", detail: "timed out"), .connectionFailed("Too many attempts."),
            ])
    }

    @Test func namesAndDetailsAppearInTheCopy() {
        #expect(CloudProblem.noAgents(organization: "Acme").title.contains("Acme"))
        #expect(CloudProblem.organizationRevoked(organization: "Acme").title.contains("Acme"))
        #expect(CloudProblem.agentUnreachable(agent: "bot", detail: "timed out").title.contains("bot"))
        #expect(CloudProblem.portalUnreachable("offline").message.hasSuffix("(offline)"))
        #expect(!CloudProblem.portalUnreachable("").message.contains("()"))
    }

    // MARK: Mapping

    @Test func portalErrorsMapOneToOne() {
        let acme = org("acme", "Acme")
        #expect(CloudProblem(portalError: CloudPortalError.notSignedIn) == .notSignedIn)
        #expect(
            CloudProblem(portalError: CloudPortalError.organizationRevoked(acme))
                == .organizationRevoked(organization: "Acme"))
        #expect(CloudProblem(portalError: CloudPortalError.unreachable("x")) == .portalUnreachable("x"))
        #expect(CloudProblem(portalError: CloudPortalError.busy(retryAfter: nil)) == .portalBusy)
        #expect(CloudProblem(portalError: CloudPortalError.unexpectedReply("x")) == .unexpectedReply("x"))
        #expect(CloudProblem(portalError: RESTError.transport("surprise")).action == .retry, "Anything else is a retry")
    }

    @Test func closingTheSignInSheetIsNoProblem() {
        #expect(CloudProblem(signInError: NativeSignInError.cancelled) == nil)
        #expect(CloudProblem(signInError: CancellationError()) == nil)
        #expect(CloudProblem(signInError: NativeSignInError.codeRejected) == .signInFailed(""))
        #expect(CloudProblem(signInError: NativeSignInError.stateMismatch) == .signInFailed(""))
        #expect(CloudProblem(signInError: NativeSignInError.server("access_denied")) == .signInFailed("access_denied"))
        #expect(CloudProblem(signInError: RESTError.transport("offline")) == .portalUnreachable("offline"))
    }

    @Test func aFailedSignInToTheAgentOffersTheSignInAgain() {
        let rejected = CloudProblem.agentSignInRejected(agent: "bot")
        #expect(CloudProblem(agentSignInError: NativeSignInError.cancelled, agent: "bot") == rejected)
        #expect(CloudProblem(agentSignInError: NativeSignInError.codeRejected, agent: "bot") == rejected)
        #expect(CloudProblem(agentSignInError: NativeSignInError.server("access_denied"), agent: "bot") == rejected)
        #expect(
            CloudProblem(agentSignInError: RESTError.transport("offline"), agent: "bot")
                == .agentUnreachable(agent: "bot", detail: "offline"))
    }

    @Test func aCompatibilityFailureSaysHermesCloudUpdatesItsAgents() {
        let problem = CloudProblem(testFailure: .serverTooOld(found: "release 2026.1.1"), agent: "bot")
        #expect(problem == .agentTooOld(agent: "bot", found: "release 2026.1.1"))
        #expect(problem.message.contains("updates its agents itself"))
        #expect(!problem.message.contains("hermes update"), "The user cannot run that on a cloud agent")
        #expect(problem.message.contains("release 2026.1.1"))
        #expect(problem.action == .retry)
    }

    @Test func connectionTestFailuresMapToCloudWords() {
        func problem(_ failure: ConnectionTestFailure) -> CloudProblem {
            CloudProblem(testFailure: failure, agent: "bot")
        }
        #expect(problem(.unreachable("offline")) == .agentUnreachable(agent: "bot", detail: "offline"))
        #expect(
            problem(.server(status: 502, detail: nil)) == .agentUnreachable(agent: "bot", detail: "it answered 502"))
        #expect(problem(.webSocket("closed")).action == .retry)
        #expect(problem(.notHermes).action == .retry)
        #expect(problem(.signInRequired(providers: [])) == .agentSignInRejected(agent: "bot"))
        #expect(problem(.wrongCredentials) == .agentSignInRejected(agent: "bot"))
        #expect(problem(.missingSecret) == .agentSignInRejected(agent: "bot"))
        #expect(problem(.rateLimited(retryAfter: 30)) == .connectionFailed("Too many attempts. Try again in a minute."))
        let failures: [ConnectionTestFailure] = [.unreachable("x"), .notHermes, .serverTooOld(found: "x")]
        for failure in failures {
            #expect(!problem(failure).message.contains("Check the address"), "Nobody typed an address")
        }
    }
}
