import Testing

@testable import HermesKit

struct OfflineChatRouterTests {
    /// A router whose server became unreachable at `time`.
    private func outage(from time: Double = 100) -> OfflineRouter {
        var router = OfflineRouter()
        router.observe(.unreachable, at: time)
        return router
    }

    private func route(
        _ router: OfflineRouter, at time: Double, enabled: Bool = true,
        availability: LocalModelAvailability = .available
    ) -> OfflineRoute {
        router.route(onDeviceEnabled: enabled, availability: availability, at: time)
    }

    // MARK: - Decisions

    @Test func aFreshRouterSendsToTheServer() {
        #expect(route(OfflineRouter(), at: 0) == .server)
        #expect(route(OfflineRouter(), at: 1_000_000) == .server)
    }

    @Test func aReachableServerGetsEveryMessage() {
        var router = OfflineRouter()
        router.observe(.reachable, at: 10)
        #expect(route(router, at: 10) == .server)
        #expect(route(router, at: 500) == .server)
    }

    @Test func graceIsThreeSeconds() {
        #expect(OfflineRouter.defaultGrace == 3)
        #expect(OfflineRouter().grace == 3)
    }

    @Test func messagesStayOnTheServerDuringTheGracePeriod() {
        let router = outage(from: 100)
        #expect(route(router, at: 100) == .server)
        #expect(route(router, at: 101.5) == .server)
        #expect(route(router, at: 102.75) == .server)
    }

    @Test func messagesGoOfflineOnceTheGracePeriodIsOver() {
        let router = outage(from: 100)
        #expect(route(router, at: 103) == .offline)
        #expect(route(router, at: 160) == .offline)
        #expect(router.offlineAt == 103)
        #expect(!router.isOutage(at: 102.75))
        #expect(router.isOutage(at: 103))
    }

    @Test func aCustomGraceMovesTheDeadline() {
        var router = OfflineRouter(grace: 10)
        router.observe(.unreachable, at: 0)
        #expect(route(router, at: 9.75) == .server)
        #expect(route(router, at: 10) == .offline)
    }

    // MARK: - Hysteresis

    @Test func aBriefDropNeverGoesOffline() {
        var router = outage(from: 100)
        router.observe(.reachable, at: 102)
        #expect(router.unreachableSince == nil)
        #expect(router.offlineAt == nil)
        #expect(route(router, at: 102) == .server)
        #expect(route(router, at: 110) == .server)
    }

    @Test func theServerIsBackTheMomentItIsReachable() {
        var router = outage(from: 100)
        #expect(route(router, at: 140) == .offline)
        router.observe(.reachable, at: 140.25)
        #expect(route(router, at: 140.25) == .server)
    }

    @Test func aSecondDropStartsTheGracePeriodAgain() {
        var router = outage(from: 100)
        router.observe(.reachable, at: 101)
        router.observe(.unreachable, at: 102)
        #expect(route(router, at: 104.5) == .server)
        #expect(route(router, at: 105) == .offline)
    }

    @Test func repeatedUnreachableReportsDoNotRestartTheTimer() {
        var router = outage(from: 100)
        router.observe(.unreachable, at: 101)
        router.observe(.unreachable, at: 102.5)
        #expect(router.unreachableSince == 100)
        #expect(route(router, at: 103) == .offline)
    }

    @Test func aRetryStepKeepsTheOutageGoing() {
        var router = outage(from: 100)
        router.observe(.unknown, at: 101)
        router.observe(.unreachable, at: 102)
        #expect(router.unreachableSince == 100)
        router.observe(.unknown, at: 102.5)
        #expect(route(router, at: 103) == .offline)
    }

    @Test func aStartUpStepAloneNeverStartsAnOutage() {
        var router = OfflineRouter()
        router.observe(.unknown, at: 100)
        #expect(router.unreachableSince == nil)
        #expect(route(router, at: 10_000) == .server)
    }

    @Test func aServerThatNeedsTheUserIsNotAnOutage() {
        var router = outage(from: 100)
        router.observe(.needsAttention, at: 101)
        #expect(router.unreachableSince == nil)
        #expect(route(router, at: 500) == .server)
    }

    // MARK: - Unavailable

    @Test func theSwitchOffMeansUnavailableInAnOutage() {
        let router = outage(from: 100)
        #expect(route(router, at: 110, enabled: false) == .unavailable(.switchedOff))
        // The switch wins over a model that says it is ready.
        #expect(route(router, at: 110, enabled: false, availability: .available) == .unavailable(.switchedOff))
    }

    @Test(arguments: [LocalModelUnavailable.unsupported, .disabled, .notReady, .switchedOff])
    func everyUnavailableReasonComesThrough(reason: LocalModelUnavailable) {
        let router = outage(from: 100)
        #expect(route(router, at: 110, availability: .unavailable(reason)) == .unavailable(reason))
    }

    @Test func theSwitchOverridesTheModelsOwnReason() {
        let router = outage(from: 100)
        let result = route(router, at: 110, enabled: false, availability: .unavailable(.disabled))
        #expect(result == .unavailable(.switchedOff))
    }

    @Test func unavailableOnlyMattersInAnOutage() {
        var router = OfflineRouter()
        router.observe(.reachable, at: 0)
        #expect(route(router, at: 10, enabled: false) == .server)
        #expect(route(router, at: 10, availability: .unavailable(.unsupported)) == .server)
        // Inside the grace period too.
        let dropping = outage(from: 100)
        #expect(route(dropping, at: 101, enabled: false) == .server)
        #expect(route(dropping, at: 101, availability: .unavailable(.notReady)) == .server)
    }

    @Test func aModelThatBecomesReadyTakesTheMessagesAtOnce() {
        let router = outage(from: 100)
        #expect(route(router, at: 120, availability: .unavailable(.notReady)) == .unavailable(.notReady))
        #expect(route(router, at: 121, availability: .available) == .offline)
    }

    // MARK: - Connection phases

    @Test func connectionPhasesAreSortedByWhatTheyMeanForReachability() {
        let cases: [(ConnectionPhase, ServerReachability)] = [
            (.connected(ServerSummary()), .reachable),
            (.idle, .unknown),
            (.unlocking, .unknown),
            (.openingTunnel, .unknown),
            (.checkingServer, .unknown),
            (.connecting, .unknown),
            (.reconnecting(attempt: 1), .unreachable),
            (.reconnecting(attempt: 9), .unreachable),
            (.signInRequired, .needsAttention),
            (.updateRequired(found: "2026.1.1"), .needsAttention),
        ]
        for (phase, expected) in cases {
            #expect(ServerReachability(phase) == expected, "\(phase)")
        }
    }

    @Test func failedAttemptsThatGotNoAnswerAreOutages() {
        let failures: [ConnectionTestFailure] = [
            .unreachable("no route to host"), .webSocket("closed"), .server(status: 502, detail: nil),
            .ssh("The SSH connection closed."),
        ]
        for failure in failures {
            #expect(ServerReachability(.failed(failure)) == .unreachable, "\(failure)")
        }
    }

    @Test func failedAttemptsTheUserMustFixAreNotOutages() {
        let failures: [ConnectionTestFailure] = [
            .notHermes, .signInRequired(providers: []), .wrongCredentials, .rateLimited(retryAfter: 30),
            .missingSecret, .hostKeyRejected, .hostKeyChanged(expected: "a", actual: "b"), .invalidForm("x"),
            .serverTooOld(found: "1"),
        ]
        for failure in failures {
            #expect(ServerReachability(.failed(failure)) == .needsAttention, "\(failure)")
        }
    }

    @Test func aRouterTakesPhasesDirectly() {
        var router = OfflineRouter()
        router.observe(ConnectionPhase.connected(ServerSummary()), at: 0)
        router.observe(ConnectionPhase.reconnecting(attempt: 1), at: 50)
        #expect(router.unreachableSince == 50)
        router.observe(ConnectionPhase.failed(.unreachable("offline")), at: 52)
        #expect(router.unreachableSince == 50)
        #expect(route(router, at: 53) == .offline)
        router.observe(ConnectionPhase.connected(ServerSummary()), at: 60)
        #expect(route(router, at: 60) == .server)
    }

    @Test func airplaneModeAtLaunchGoesOfflineThreeSecondsAfterTheFailure() {
        // idle -> checking the server -> the check fails at once (no network).
        var router = OfflineRouter()
        router.observe(ConnectionPhase.idle, at: 0)
        router.observe(ConnectionPhase.checkingServer, at: 0.25)
        router.observe(ConnectionPhase.failed(.unreachable("The Internet connection appears to be offline.")), at: 0.5)
        #expect(route(router, at: 3.25) == .server)
        #expect(route(router, at: 3.5) == .offline)
    }
}
