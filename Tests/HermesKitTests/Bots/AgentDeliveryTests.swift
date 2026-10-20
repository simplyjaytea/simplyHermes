import Foundation
import Testing

@testable import HermesKit

@Suite struct AgentDeliveryTests {
    @Test func queuedReceiptMustNotBeResent() throws {
        let receipt = try #require(
            AgentDeliveryReceipt.parse(#"{"status": "queued", "delivery_id": "d1", "to": "ops"}"#))
        #expect(receipt.status == .queued)
        #expect(receipt.deliveryID == "d1")
        #expect(receipt.target == "ops")
        #expect(receipt.mustNotResend)
        #expect(!receipt.isTerminal)
        #expect(receipt.label == "Sent. Waiting for a reply.")
    }

    @Test func settledIsTerminalAndAmbiguousSaysDoNotResend() throws {
        let settled = try #require(AgentDeliveryReceipt.parse(#"{"status": "settled"}"#))
        #expect(settled.isTerminal)
        #expect(!settled.mustNotResend)
        #expect(settled.label == "Delivered.")

        let ambiguous = try #require(AgentDeliveryReceipt.parse(#"{"status": "ambiguous"}"#))
        #expect(ambiguous.mustNotResend)
        #expect(!ambiguous.isTerminal)
        #expect(ambiguous.label == "Unknown whether it arrived. Do not resend.")
    }

    @Test func failedReceiptNamesTheReason() throws {
        let failed = try #require(AgentDeliveryReceipt.parse(#"{"status": "failed", "reason": "target_busy"}"#))
        #expect(failed.isTerminal)
        #expect(failed.label == "Not delivered. The bot is busy in another chat.")
    }

    @Test func refusalHasNoStatusAndReadsAsNotSent() throws {
        let refused = try #require(
            AgentDeliveryReceipt.parse(#"{"error": "no such bot", "reason": "target_scope_unresolved"}"#))
        #expect(refused.status == nil)
        #expect(refused.label == "Not sent. No bot matches that name.")
        #expect(AgentDeliveryReceipt.parse(#"{"detail": "x"}"#) == nil)
        #expect(AgentDeliveryReceipt.parse("plain text") == nil)
    }

    @Test func outcomeNotificationsParse() {
        #expect(
            AgentDeliveryOutcome.parse("Reply from ops:\nHello there")
                == AgentDeliveryOutcome.replied(from: "ops", reply: "Hello there"))
        #expect(
            AgentDeliveryOutcome.parse("Delivery to ops failed [reason: target_busy]: The bot is busy.")
                == AgentDeliveryOutcome.failed(target: "ops", reason: "target_busy", error: "The bot is busy."))
        #expect(
            AgentDeliveryOutcome.parse("No reply from ops within 120s")
                == AgentDeliveryOutcome.timedOut(from: "ops", seconds: 120))
        #expect(AgentDeliveryOutcome.parse("Something else") == nil)
    }

    @Test func agentMessageNoticesParseBothForms() throws {
        let named = try #require(AgentMessageNotice.parse("Message from Research Bot (@research): Found it"))
        #expect(named.sender == "Research Bot")
        #expect(named.senderHandle == "research")
        #expect(named.body == "Found it")

        let bracketed = try #require(AgentMessageNotice.parse("[Message from agent 'ops']\nDo the thing"))
        #expect(bracketed.sender == "ops")
        #expect(bracketed.senderHandle == nil)
        #expect(bracketed.body == "Do the thing")

        #expect(AgentMessageNotice.parse("Just a user message") == nil)
    }
}
