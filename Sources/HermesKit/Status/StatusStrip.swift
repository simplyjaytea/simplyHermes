import Foundation

/// One figure the status strip can show.
public enum StatusItem: String, Sendable, CaseIterable, Codable {
    /// Context window use.
    case context
    /// Prompt cache hit rate.
    case cache
    /// Average tokens per second.
    case speed
    /// Total tokens of the session.
    case tokens
    /// Cost in US dollars.
    case cost
    /// Subagents running now.
    case subagents
    /// Connection state.
    case connection
}

/// How full the context window is.
public enum ContextLevel: Sendable, Equatable {
    /// Plenty of room.
    case normal
    /// Getting full: the agent may compress soon.
    case warning
    /// Almost full.
    case critical
}

/// The connection state as the strip shows it.
public enum StripConnection: Sendable, Equatable {
    /// Connected.
    case online
    /// Connecting, or waiting to retry.
    case reconnecting
    /// Not connected.
    case offline
    /// Stopped until the user fixes something such as signing in.
    case needsAttention

    /// Maps the gateway client's state.
    public init(_ state: GatewayConnectionState) {
        switch state {
        case .connected: self = .online
        case .connecting, .waitingToReconnect: self = .reconnecting
        case .idle, .stopped: self = .offline
        case .failed: self = .needsAttention
        }
    }
}

/// The text and tone of one strip item.
public struct StatusReading: Sendable, Equatable, Identifiable {
    /// Which item.
    public var item: StatusItem
    /// Short value such as `42%`, `1.2k` or `118 tok/s`.
    public var value: String
    /// True when the number is an estimate (shown with `~`).
    public var estimated: Bool
    /// Set for ``StatusItem/context`` only.
    public var level: ContextLevel?

    /// The item, for `ForEach`.
    public var id: StatusItem { item }
}

/// The token breakdown behind the context meter, for the detail sheet.
public struct TokenBreakdown: Sendable, Equatable {
    /// Prompt tokens.
    public var prompt: Int
    /// Completion tokens.
    public var completion: Int
    /// Reasoning tokens.
    public var reasoning: Int
    /// Tokens read from the cache, when reported.
    public var cacheRead: Int?
    /// Tokens written to the cache, when reported.
    public var cacheWrite: Int?
    /// Tokens in the context now, when reported.
    public var contextUsed: Int?
    /// Size of the context window, when reported.
    public var contextMax: Int?
    /// Context compressions so far.
    public var compressions: Int
}

/// Turns the latest ``Usage`` and the connection state into the readings of the status strip.
public struct StatusStrip: Sendable, Equatable {
    /// Context use at or above this percentage is a warning.
    public static let warningPercent = 75.0
    /// Context use at or above this percentage is critical.
    public static let criticalPercent = 90.0
    /// What a new install shows.
    public static let defaultItems: [StatusItem] = [.context, .cache, .speed, .connection]

    /// The latest usage snapshot, if the session has one.
    public var usage: Usage?
    /// The connection state.
    public var connection: StripConnection

    /// Creates a strip model.
    public init(usage: Usage?, connection: StripConnection) {
        self.usage = usage
        self.connection = connection
    }

    /// Context use as a percentage, from used and max when both are known, else the server's figure.
    ///
    /// The server rounds `context_percent` down to a whole number, so a small use shows `0`.
    public var contextPercent: Double? {
        guard let usage else { return nil }
        if let used = usage.contextUsed, let limit = usage.contextMax, limit > 0 {
            return min(100, Double(used) / Double(limit) * 100)
        }
        return usage.contextPercent
    }

    /// How full the context is. Nil when unknown.
    public var contextLevel: ContextLevel? {
        guard let percent = contextPercent else { return nil }
        if percent >= Self.criticalPercent { return .critical }
        return percent >= Self.warningPercent ? .warning : .normal
    }

    /// The token breakdown, or nil before the first usage snapshot.
    public var breakdown: TokenBreakdown? {
        guard let usage else { return nil }
        return TokenBreakdown(
            prompt: usage.prompt, completion: usage.completion, reasoning: usage.reasoning, cacheRead: usage.cacheRead,
            cacheWrite: usage.cacheWrite, contextUsed: usage.contextUsed, contextMax: usage.contextMax,
            compressions: usage.compressions ?? 0)
    }

    /// The readings for `items`, in that order. Items with no data yet are left out, except the connection.
    public func readings(_ items: [StatusItem]) -> [StatusReading] {
        items.compactMap(reading)
    }

    /// The reading of one item, or nil when there is no data for it.
    public func reading(_ item: StatusItem) -> StatusReading? {
        switch item {
        case .connection:
            return StatusReading(item: item, value: Self.text(connection), estimated: false, level: nil)
        case .context:
            guard let percent = contextPercent else { return nil }
            let value = percent > 0 && percent < 1 ? "<1%" : "\(Int(percent.rounded()))%"
            return StatusReading(
                item: item, value: value, estimated: usage?.contextEstimated ?? false, level: contextLevel)
        case .cache:
            guard let rate = usage?.cacheHitPct else { return nil }
            return StatusReading(item: item, value: "\(Int(rate.rounded()))%", estimated: false, level: nil)
        case .speed:
            guard let speed = usage?.avgTokensPerSecond, speed > 0 else { return nil }
            return StatusReading(item: item, value: "\(Int(speed.rounded())) tok/s", estimated: false, level: nil)
        case .tokens:
            guard let usage else { return nil }
            return StatusReading(item: item, value: Self.compact(usage.total), estimated: false, level: nil)
        case .cost:
            guard let cost = usage?.costUSD else { return nil }
            let estimated = usage?.costStatus.map { $0 != "actual" && $0 != "known" } ?? false
            return StatusReading(item: item, value: Self.money(cost), estimated: estimated, level: nil)
        case .subagents:
            guard let count = usage?.activeSubagents, count > 0 else { return nil }
            return StatusReading(item: item, value: "\(count)", estimated: false, level: nil)
        }
    }

    /// `999`, `1.2k`, `15k`, `1.4M`.
    public static func compact(_ count: Int) -> String {
        switch count {
        case ..<1000: return String(count)
        case ..<10_000: return trimmed(Double(count) / 1000) + "k"
        case ..<1_000_000: return "\(Int((Double(count) / 1000).rounded()))k"
        default: return trimmed(Double(count) / 1_000_000) + "M"
        }
    }

    private static func trimmed(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private static func money(_ value: Double) -> String {
        value < 0.01 && value > 0 ? "<$0.01" : String(format: "$%.2f", value)
    }

    private static func text(_ connection: StripConnection) -> String {
        switch connection {
        case .online: "Online"
        case .reconnecting: "Reconnecting"
        case .offline: "Offline"
        case .needsAttention: "Sign in"
        }
    }
}

/// The readings model under a name that does not clash with the `StatusStrip` view in HermesUI.
public typealias ChatStatusStrip = StatusStrip
