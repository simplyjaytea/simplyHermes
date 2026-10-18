import Foundation

/// Errors the server-control code raises itself. Screens show ``describe(_:)`` instead of raw error text.
public enum ServerControlError: Error, Sendable, Equatable {
    /// The server is not connected: there is no connection manager, or the connection did not come up.
    case notConnected

    /// One or two sentences for an alert or a status line.
    public static func describe(_ error: any Error) -> String {
        if let failure = error as? ConnectionTestFailure { return failure.message }
        if error is ConnectionUnavailable {
            return "Couldn't connect to this server. Try Connect in Settings > Servers."
        }
        if error is CancellationError { return "Cancelled." }
        if let own = error as? ServerControlError {
            switch own {
            case .notConnected: return "Couldn't reach this server. Check that it is connected."
            }
        }
        if let rest = error as? RESTError {
            switch rest {
            case .unauthorized: return "Sign in to this server again in Settings > Servers."
            case .rateLimited: return "The server is busy. Try again in a minute."
            case .http(let status, let detail): return detail ?? "The server answered with status \(status)."
            case .unexpectedContent: return "The server sent a web page instead of an answer. Check the address."
            case .transport: return "The server did not answer."
            case .decoding: return "The server's answer was not what the app expects."
            }
        }
        return "Something went wrong. Try again."
    }
}
