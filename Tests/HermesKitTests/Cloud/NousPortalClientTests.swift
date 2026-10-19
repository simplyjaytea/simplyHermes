import Foundation
import HermesKit
import Testing

/// WP-17: the guessed portal routes and shapes, against a stub transport and hand-written fixtures. These tests pin
/// what the code assumes; they prove nothing about the real portal.
@Suite struct NousPortalClientTests {
    private func client(_ http: FakeHTTP) -> NousPortalClient {
        NousPortalClient(makeTransport: { http })
    }

    private let acme = CloudOrganization(id: "org_acme", name: "Acme Research")

    @Test func listsOrganizationsWithTheBearerToken() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try cloudFixture("organizations"))
        let list = try await client(http).organizations(accessToken: "tok-1")
        #expect(
            list.map(\.id) == ["org_acme", "org_home", "org_acme"], "The client reports what the portal said")
        #expect(list.map(\.name) == ["Acme Research", "Home lab", "Acme Research (repeat)"])
        let request = try #require(http.requests.first)
        #expect(request.method == "GET")
        #expect(request.url.absoluteString == "https://portal.nousresearch.com/api/organizations")
        #expect(request.headers["Authorization"] == "Bearer tok-1")
        #expect(http.requests.count == 1)
    }

    @Test func readsABareArrayAndNumericIds() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try cloudFixture("organizations_array"))
        let list = try await client(http).organizations(accessToken: "t")
        #expect(list == [CloudOrganization(id: "7", name: "Solo")])
    }

    @Test func emptyListsAreAnswersNotErrors() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"organizations":[]}"#)
        http.enqueue(200, "[]")
        let portal = client(http)
        #expect(try await portal.organizations(accessToken: "t").isEmpty)
        #expect(try await portal.agents(in: acme, accessToken: "t").isEmpty)
    }

    @Test func listsAgentsAndKeepsOnlyUsableOnes() async throws {
        let http = FakeHTTP()
        http.enqueue(200, try cloudFixture("agents"))
        let agents = try await client(http).agents(in: acme, accessToken: "tok-2")
        let request = try #require(http.requests.first)
        #expect(request.url.absoluteString == "https://portal.nousresearch.com/api/organizations/org_acme/agents")
        #expect(request.headers["Authorization"] == "Bearer tok-2")
        // The plain-HTTP agent and the agent without an address are dropped: the sign-in tokens go to that address.
        // The repeat is kept here; CloudSelection lists each agent once.
        #expect(agents.map(\.id) == ["agt_1", "agt_2", "3", "agt_1"])
        #expect(agents[0].name == "research-bot")
        #expect(agents[0].endpoint.baseURL.absoluteString == "https://research-bot.acme.example")
        #expect(agents[1].name == "Night shift")
        #expect(agents[1].status == .stopped)
        #expect(agents[1].endpoint.baseURL.path == "/hermes")
        #expect(agents[2].status == .starting)
        #expect(agents[2].endpoint.baseURL.host == "numeric.acme.example")
    }

    @Test func agentsWithNoUsableAddressAreAnUnreadableReply() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"agents":[{"id":"a","name":"x","url":"http://203.0.113.7"},{"id":"b","name":"y"}]}"#)
        await #expect(throws: CloudPortalError.unexpectedReply("none of the 2 agents had an HTTPS address")) {
            _ = try await client(http).agents(in: acme, accessToken: "t")
        }
    }

    @Test func idsThatCouldChangeTheRouteAreRefused() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"organizations":[{"id":"a/b","name":"Slash"},{"id":"ok","name":"Fine"}]}"#)
        let list = try await client(http).organizations(accessToken: "t")
        #expect(list == [CloudOrganization(id: "ok", name: "Fine")])
    }

    // MARK: Failures

    @Test func unauthorizedMeansSignInAgain() async {
        let http = FakeHTTP()
        http.enqueue(401, #"{"detail":"expired"}"#)
        await #expect(throws: CloudPortalError.notSignedIn) {
            _ = try await client(http).organizations(accessToken: "t")
        }
    }

    @Test func forbiddenOnTheAgentsRouteMeansTheOrganizationWasRevoked() async {
        let http = FakeHTTP()
        http.enqueue(403, #"{"detail":"not a member"}"#)
        await #expect(throws: CloudPortalError.organizationRevoked(acme)) {
            _ = try await client(http).agents(in: acme, accessToken: "t")
        }
    }

    @Test func forbiddenOnTheOrganizationsRouteMeansSignInAgain() async {
        let http = FakeHTTP()
        http.enqueue(403)
        await #expect(throws: CloudPortalError.notSignedIn) {
            _ = try await client(http).organizations(accessToken: "t")
        }
    }

    @Test func aMissingRouteIsAnUnreadableReplyNotARevocation() async {
        let http = FakeHTTP()
        http.enqueue(404, #"{"detail":"Not Found"}"#)
        await #expect(throws: CloudPortalError.unexpectedReply("status 404: Not Found")) {
            _ = try await client(http).agents(in: acme, accessToken: "t")
        }
    }

    @Test func anHTMLPageIsAnUnreadableReply() async {
        let http = FakeHTTP()
        http.enqueue(200, "<html>Sign in</html>", headers: ["Content-Type": "text/html; charset=utf-8"])
        await #expect(throws: CloudPortalError.unexpectedReply("not JSON (text/html; charset=utf-8)")) {
            _ = try await client(http).organizations(accessToken: "t")
        }
    }

    @Test func anUnknownShapeIsAnUnreadableReply() async throws {
        let http = FakeHTTP()
        http.enqueue(200, #"{"results":[]}"#)
        do {
            _ = try await client(http).organizations(accessToken: "t")
            Issue.record("expected an error")
        } catch CloudPortalError.unexpectedReply {
            // expected
        }
    }

    @Test func serverErrorsAndMissingAnswersAreUnreachable() async {
        let http = FakeHTTP()
        http.enqueue(503)
        await #expect(throws: CloudPortalError.unreachable("Hermes Cloud answered 503")) {
            _ = try await client(http).organizations(accessToken: "t")
        }
        // Nothing is queued now: the stub transport throws, like a dropped connection.
        await #expect(throws: CloudPortalError.unreachable("no scripted response")) {
            _ = try await client(http).organizations(accessToken: "t")
        }
    }

    @Test func tooManyRequestsAreBusyWithoutWaiting() async {
        let http = FakeHTTP()
        http.enqueue(429, "{}")
        await #expect(throws: CloudPortalError.busy(retryAfter: nil)) {
            _ = try await client(http).organizations(accessToken: "t")
        }
        #expect(http.requests.count == 1, "No retry: the screen says so and lets the user try again")
    }

    @Test func statusWordsMapToCaptions() {
        #expect(CloudAgent.Status(portalValue: " Running ") == .running)
        #expect(CloudAgent.Status(portalValue: "provisioning") == .starting)
        #expect(CloudAgent.Status(portalValue: "SUSPENDED") == .stopped)
        #expect(CloudAgent.Status(portalValue: "weird") == .unknown)
        #expect(CloudAgent.Status(portalValue: nil).caption == nil)
        #expect(CloudAgent.Status.running.caption == "Running")
    }
}
