import Foundation

/// The `cron.changed` event: the gateway says the cron job store changed. It carries no payload, so the listener
/// reloads the list from REST when it sees one.
public enum CronChangeSignal {
    /// True for a `cron.changed` event from the gateway.
    public static func isChange(_ event: GatewayClientEvent) -> Bool {
        guard case .event(let envelope, _) = event else { return false }
        return envelope.event == .cronChanged
    }
}
