import Foundation

/// What `message_agent` reported when it accepted, refused or could not confirm a message. The result is the tool's
/// JSON string (`tool.complete.result`). The outcome arrives later, as a completion notification (plan 2.5, WP-42).
public struct AgentDeliveryReceipt: Sendable, Equatable {
    public enum Status: String, Sendable, Equatable, CaseIterable {
        case queued, claimed, settled, failed, cancelled, ambiguous
    }

    /// Nil when the message was refused before it was sent.
    public var status: Status?
    public var deliveryID: String?
    public var target: String?
    /// A failure code from `BotDeliveryReason`, such as `target_busy`.
    public var reason: String?
    public var detail: String?
    public var error: String?

    public init(
        status: Status? = nil, deliveryID: String? = nil, target: String? = nil, reason: String? = nil,
        detail: String? = nil, error: String? = nil
    ) {
        self.status = status
        self.deliveryID = deliveryID
        self.target = target
        self.reason = reason
        self.detail = detail
        self.error = error
    }

    /// The states after which nothing more arrives.
    public var isTerminal: Bool {
        status == .settled || status == .failed || status == .cancelled
    }

    /// The states where the tool itself says not to resend: the message may already be with the bot.
    public var mustNotResend: Bool {
        status == .queued || status == .claimed || status == .ambiguous
    }

    /// The line a user reads under the message.
    public var label: String {
        switch status {
        case .queued?: return "Sent. Waiting for a reply."
        case .claimed?: return "Received. Working on it."
        case .settled?: return "Delivered."
        case .cancelled?: return "Cancelled."
        case .ambiguous?: return "Unknown whether it arrived. Do not resend."
        case .failed?: return "Not delivered. " + BotDeliveryReason.label(for: reason)
        case nil: return "Not sent. " + BotDeliveryReason.label(for: reason ?? error.map { _ in "unknown" })
        }
    }
}

/// Labels for the failure codes `message_agent` reports.
public enum BotDeliveryReason {
    public static func label(for code: String?) -> String {
        switch code {
        case "runtime_offline": return "The bot is offline."
        case "queued_expired": return "It expired before the bot picked it up."
        case "delivery_timeout": return "No reply in time."
        case "agent_blocked": return "The bot is waiting on an approval."
        case "cancelled": return "Cancelled."
        case "provider_auth_or_access": return "The bot's provider refused the sign-in."
        case "provider_quota_limit": return "The bot's provider is out of quota."
        case "provider_rate_limit": return "The bot's provider is rate limiting."
        case "provider_server_error": return "The bot's provider failed."
        case "context_overflow": return "The bot's chat is too long."
        case "missing_config": return "The bot is missing configuration."
        case "model_unavailable": return "The bot's model is unavailable."
        case "target_scope_unresolved": return "No bot matches that name."
        case "target_busy": return "The bot is busy in another chat."
        default: return "Something went wrong."
        }
    }
}

/// The text of a `message_agent` outcome, from the background completion notification.
public enum AgentDeliveryOutcome: Sendable, Equatable {
    case replied(from: String, reply: String)
    case failed(target: String, reason: String?, error: String)
    case timedOut(from: String, seconds: Int)

    public static func parse(_ text: String) -> AgentDeliveryOutcome? {
        if text.hasPrefix("Reply from "), let colon = text.range(of: ":\n") {
            let from = String(text[text.index(text.startIndex, offsetBy: "Reply from ".count)..<colon.lowerBound])
            return .replied(from: from, reply: String(text[colon.upperBound...]))
        }
        if text.hasPrefix("Delivery to "), let failed = text.range(of: " failed [reason: ") {
            let target = String(text[text.index(text.startIndex, offsetBy: "Delivery to ".count)..<failed.lowerBound])
            let rest = text[failed.upperBound...]
            guard let close = rest.range(of: "]: ") else { return nil }
            let reason = String(rest[..<close.lowerBound])
            return .failed(target: target, reason: reason, error: String(rest[close.upperBound...]))
        }
        if text.hasPrefix("No reply from "), let within = text.range(of: " within ") {
            let from = String(text[text.index(text.startIndex, offsetBy: "No reply from ".count)..<within.lowerBound])
            let seconds = text[within.upperBound...].prefix { $0.isNumber }
            guard let value = Int(seconds) else { return nil }
            return .timedOut(from: from, seconds: value)
        }
        return nil
    }
}

extension AgentDeliveryReceipt {
    /// Parses a `message_agent` result. Nil when the text is not that tool's JSON.
    public static func parse(_ result: String) -> AgentDeliveryReceipt? {
        guard let data = result.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let status = (object["status"] as? String).flatMap(Status.init(rawValue:))
        let reason = object["reason"] as? String
        let error = object["error"] as? String
        // A refusal has an error and no status. Anything else without a known status is not a receipt.
        if status == nil && error == nil { return nil }
        return AgentDeliveryReceipt(
            status: status, deliveryID: object["delivery_id"] as? String, target: object["to"] as? String,
            reason: reason, detail: object["detail"] as? String, error: error)
    }
}

/// A message a bot received from another bot, as Desktop shows it: `Message from <sender>: <body>`.
public struct AgentMessageNotice: Sendable, Equatable {
    public var sender: String
    public var senderHandle: String?
    public var body: String

    /// Desktop's pattern (`AGENT_MESSAGE_RE`, `thread/user-message.tsx`). Nil for an ordinary user message.
    private static let pattern =
        #"^(?:Message from (?:🤖\s*)?([^:\n(]{1,64}?)"#
        + #"(?:\s*\(@([a-z0-9][a-z0-9_-]{0,63})(?:@[a-zA-Z0-9][a-zA-Z0-9_-]{0,63})?\))?:\s*"#
        + #"|\[Message from agent '([^']{1,64})'\]\s*)([\s\S]*)$"#

    public static func parse(_ text: String) -> AgentMessageNotice? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        func group(_ index: Int) -> String? {
            let range = match.range(at: index)
            guard range.location != NSNotFound, let swiftRange = Range(range, in: text) else { return nil }
            return String(text[swiftRange])
        }
        guard let sender = group(1) ?? group(3) else { return nil }
        return AgentMessageNotice(
            sender: sender.trimmingCharacters(in: .whitespaces), senderHandle: group(2), body: group(4) ?? "")
    }
}
