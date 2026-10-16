import Foundation
import Testing

@testable import HermesKit

@Suite struct ChatErrorTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    @Test func rateLimitReadsTheRetryDelay() {
        let error = ChatError.classify("Error 429: rate limit reached, try again in 30 seconds", now: now)
        #expect(error.layer == .provider)
        #expect(error.kind == .rateLimit)
        #expect(error.retryAt == now.addingTimeInterval(30))
        #expect(error.isRetryable)
    }

    @Test func minutesAreScaled() {
        let error = ChatError.classify("Too many requests. Retry after 2 minutes", now: now)
        #expect(error.retryAt == now.addingTimeInterval(120))
    }

    @Test func rateLimitWithoutAHintHasNoRetryTime() {
        #expect(ChatError.classify("rate limit exceeded", now: now).retryAt == nil)
    }

    @Test func authenticationIsNotRetryable() {
        let error = ChatError.classify("401 Unauthorized: invalid API key", now: now)
        #expect(error.kind == .authentication)
        #expect(!error.isRetryable)
    }

    @Test func networkAndOverloadAreSeparated() {
        #expect(ChatError.classify("request timed out", now: now).layer == .network)
        #expect(ChatError.classify("Connection reset by peer", now: now).kind == .offline)
        #expect(ChatError.classify("provider overloaded (529)", now: now).kind == .overloaded)
        #expect(ChatError.classify("prompt is too long for this model", now: now).kind == .contextTooLong)
    }

    @Test func unknownTextKeepsTheMessage() {
        let error = ChatError.classify("something odd", now: now)
        #expect(error.layer == .unknown)
        #expect(error.message == "something odd")
        #expect(!error.isRetryable)
    }
}
