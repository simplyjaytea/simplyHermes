import Foundation
import HermesKit
import Testing

/// Words for failures on the memory screen (WP-52).
@Suite struct JourneyErrorTextTests {
    private func text(_ error: any Error, _ action: JourneyErrorText.Action = .load) -> String {
        JourneyErrorText.message(for: error, doing: action)
    }

    @Test func eachActionNamesWhatFailed() {
        let error = RESTError.transport("down")
        #expect(text(error, .load).hasPrefix("Could not load memory."))
        #expect(text(error, .open).hasPrefix("Could not open that item."))
        #expect(text(error, .save).hasPrefix("Could not save your change."))
        #expect(text(error, .delete).hasPrefix("Could not delete that item."))
    }

    @Test func connectionProblemsExplainThemselves() {
        #expect(text(ConnectionUnavailable(phase: .idle)).hasSuffix("The server is not reachable."))
        #expect(text(ConnectionUnavailable(phase: .signInRequired)).hasSuffix("The server wants you to sign in again."))
        #expect(text(ConnectionUnavailable(phase: .updateRequired(found: "0.9"))).contains("too old"))
        #expect(text(ConnectionUnavailable(phase: .failed(.wrongCredentials))).contains("refused the sign-in"))
    }

    @Test func restFailuresGetOneSentenceEach() {
        #expect(text(RESTError.unauthorized).hasSuffix("The server wants you to sign in again."))
        #expect(text(RESTError.transport("x")).hasSuffix("There was no answer from the server. Check the connection."))
        #expect(text(RESTError.decoding("x")).hasSuffix("The server sent data the app could not read."))
        #expect(text(RESTError.unexpectedContent(contentType: "text/html")).contains("web page"))
    }

    @Test func busyServersSayHowLongToWait() {
        #expect(text(RESTError.rateLimited(retryAfter: 7)).hasSuffix("Try again in 7 seconds."))
        #expect(text(RESTError.rateLimited(retryAfter: 6.2)).hasSuffix("Try again in 7 seconds."))
        #expect(text(RESTError.rateLimited(retryAfter: 1)).hasSuffix("Try again in 1 second."))
        #expect(text(RESTError.rateLimited(retryAfter: nil)).hasSuffix("Try again in a minute."))
        #expect(text(RESTError.rateLimited(retryAfter: .infinity)).hasSuffix("Try again in a minute."))
        #expect(text(RESTError.rateLimited(retryAfter: 1e9)).hasSuffix("Try again in 3600 seconds."))
        #expect(text(RESTError.rateLimited(retryAfter: -3)).hasSuffix("Try again in a minute."))
    }

    @Test func theServersReasonIsShownWhenItGivesOne() {
        #expect(
            text(RESTError.http(status: 400, detail: "SKILL.md needs a name."), .save).hasSuffix(
                "The server said: SKILL.md needs a name."))
        #expect(
            text(RESTError.http(status: 404, detail: "  Unknown profile: nope \n"), .load).hasSuffix(
                "The server said: Unknown profile: nope"))
    }

    @Test func pinnedSkillsGetATipOnDelete() {
        let refusal = RESTError.http(status: 409, detail: "x is pinned. Unpin it before deleting.")
        let message = text(refusal, .delete)
        #expect(message.contains("pinned, so it cannot be deleted") && message.contains("Unpin it on the server"))
        #expect(message.contains("x is pinned."), "the server's own words stay in")
        #expect(text(refusal, .save).hasSuffix("The server said: x is pinned. Unpin it before deleting."))
    }

    @Test func statusAloneStillMakesSense() {
        #expect(text(RESTError.http(status: 404, detail: nil), .load).contains("older Hermes"))
        #expect(text(RESTError.http(status: 404, detail: nil), .open).contains("cannot find that item"))
        #expect(text(RESTError.http(status: 404, detail: ""), .delete).contains("cannot find that item"))
        #expect(text(RESTError.http(status: 503, detail: nil)).contains("(503)"))
        #expect(text(RESTError.http(status: 418, detail: nil)).hasSuffix("The server refused the request (418)."))
    }

    @Test func otherErrorsGetAPlainRetry() {
        struct Odd: Error {}
        #expect(text(Odd(), .save) == "Could not save your change. Try again.")
    }
}
