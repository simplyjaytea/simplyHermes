import Foundation

/// A failed turn, classified from the error text so the chat can say which layer failed and what to do.
public struct ChatError: Sendable, Equatable {
    /// Which layer failed.
    public enum Layer: String, Sendable, Equatable {
        /// The model provider refused or failed the request.
        case provider
        /// The connection between the phone, the gateway and the provider.
        case network
        /// A tool the agent called.
        case tool
        /// Anything else, including errors with no recognisable cause.
        case unknown
    }

    /// What went wrong, in the terms the user can act on.
    public enum Kind: String, Sendable, Equatable {
        case rateLimit
        case authentication
        case overloaded
        case contextTooLong
        case timeout
        case offline
        case unknown
    }

    public var layer: Layer
    public var kind: Kind
    /// The server's text, unchanged. Shown under the summary and copied by Copy.
    public var message: String
    /// When a rate limit lifts, when the text says so.
    public var retryAt: Date?

    /// True when sending the same prompt again can help without changing anything.
    public var isRetryable: Bool {
        switch kind {
        case .rateLimit, .overloaded, .timeout, .offline: true
        case .authentication, .contextTooLong, .unknown: false
        }
    }

    /// Classifies an error. `now` anchors "try again in 30 seconds" style hints.
    public static func classify(_ text: String, now: Date = Date()) -> ChatError {
        let lower = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { lower.contains($0) } }
        let (layer, kind): (Layer, Kind)
        if has(["rate limit", "rate_limit", "429", "too many requests", "quota"]) {
            (layer, kind) = (.provider, .rateLimit)
        } else if has([
            "401", "403", "unauthorized", "invalid api key", "invalid_api_key", "authentication", "forbidden",
        ]) {
            (layer, kind) = (.provider, .authentication)
        } else if has(["overloaded", "529", "503", "502", "500", "service unavailable", "bad gateway"]) {
            (layer, kind) = (.provider, .overloaded)
        } else if has(["context length", "context_length", "maximum context", "too many tokens", "prompt is too long"])
        {
            (layer, kind) = (.provider, .contextTooLong)
        } else if has(["timed out", "timeout"]) {
            (layer, kind) = (.network, .timeout)
        } else if has(["connection", "network", "offline", "unreachable", "dns"]) {
            (layer, kind) = (.network, .offline)
        } else if has(["tool call", "tool failed", "tool error"]) {
            (layer, kind) = (.tool, .unknown)
        } else {
            (layer, kind) = (.unknown, .unknown)
        }
        let retryAt = kind == .rateLimit ? retryDelay(in: lower).map { now.addingTimeInterval($0) } : nil
        return ChatError(layer: layer, kind: kind, message: text, retryAt: retryAt)
    }

    /// Reads "in 30 seconds", "after 2 minutes", "retry-after: 45" or "1m30s" hints.
    static func retryDelay(in lower: String) -> TimeInterval? {
        let patterns: [(String, Double)] = [
            (#"retry-after:?\s*(\d+)"#, 1),
            (#"(\d+)\s*(?:seconds|second|secs|sec|s)\b"#, 1),
            (#"(\d+)\s*(?:minutes|minute|mins|min|m)\b"#, 60),
        ]
        for (pattern, scale) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
                let range = Range(match.range(at: 1), in: lower), let value = Double(lower[range])
            else { continue }
            return value * scale
        }
        return nil
    }
}
