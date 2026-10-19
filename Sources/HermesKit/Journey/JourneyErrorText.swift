import Foundation

/// Plain words for what went wrong on the memory screen. One sentence says what failed and one says why.
public enum JourneyErrorText {
    /// What the app was doing when it failed.
    public enum Action: Sendable, Equatable {
        /// Loading the graph.
        case load
        /// Opening a node to read or edit it.
        case open
        /// Saving an edit.
        case save
        /// Deleting a node.
        case delete
    }

    /// The text to show for `error`, which happened while the app was doing `action`.
    public static func message(for error: any Error, doing action: Action) -> String {
        "\(failure(of: action)) \(reason(for: error, doing: action))"
    }

    private static func failure(of action: Action) -> String {
        switch action {
        case .load: "Could not load memory."
        case .open: "Could not open that item."
        case .save: "Could not save your change."
        case .delete: "Could not delete that item."
        }
    }

    private static func reason(for error: any Error, doing action: Action) -> String {
        if let unavailable = error as? ConnectionUnavailable { return reason(for: unavailable.phase) }
        guard let error = error as? RESTError else { return "Try again." }
        switch error {
        case .unauthorized:
            return "The server wants you to sign in again."
        case .rateLimited(let retryAfter):
            return "The server is busy. Try again \(wait(retryAfter))."
        case .http(let status, let detail):
            return reason(status: status, detail: detail, doing: action)
        case .unexpectedContent:
            return "The server answered with a web page, not data. Check the address and that you are signed in."
        case .transport:
            return "There was no answer from the server. Check the connection."
        case .decoding:
            return "The server sent data the app could not read."
        }
    }

    private static func reason(for phase: ConnectionPhase) -> String {
        switch phase {
        case .signInRequired: "The server wants you to sign in again."
        case .updateRequired(let found):
            "This Hermes is too old for simplyHermes (\(found)). Update Hermes on the server."
        case .failed(let failure): failure.message
        default: "The server is not reachable."
        }
    }

    private static func reason(status: Int, detail: String?, doing action: Action) -> String {
        let trimmed = detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if action == .delete, trimmed.localizedCaseInsensitiveContains("pinned") {
            return "That skill is pinned, so it cannot be deleted. Unpin it on the server first. (\(trimmed))"
        }
        if !trimmed.isEmpty { return "The server said: \(trimmed)" }
        switch status {
        case 404 where action == .load: return "This server has no memory graph. It may run an older Hermes."
        case 404: return "The server cannot find that item. It may have been removed already."
        case 500...599: return "The server had a problem (\(status)). Try again in a moment."
        default: return "The server refused the request (\(status))."
        }
    }

    /// `in 7 seconds`, `in 1 second`, or `in a minute` when the server gave no usable hint.
    private static func wait(_ retryAfter: Double?) -> String {
        guard let retryAfter, retryAfter.isFinite, retryAfter > 0 else { return "in a minute" }
        let seconds = Int(min(retryAfter.rounded(.up), 3_600))
        return seconds == 1 ? "in 1 second" : "in \(seconds) seconds"
    }
}
