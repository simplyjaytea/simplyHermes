import Foundation

/// The actions the glass banner offers when an online chat cannot reach its server.
public enum OutageAction: Sendable, Equatable, CaseIterable {
    /// Connect again now.
    case tryAgain
    /// Open a new Local chat with the draft. The online chat stays as it is.
    case continueInNewLocalChat

    /// The button's text (UX spec §3, Poppy rev 2).
    public var title: String {
        switch self {
        case .tryAgain: "Try again"
        case .continueInNewLocalChat: "Continue in a new Local chat"
        }
    }
}

/// The "Can't reach {server}" banner above the composer. It shows only when the chat's status is unreachable.
public enum OutageBanner {
    /// True when the banner shows for this status.
    public static func shows(_ status: ChatStatus) -> Bool {
        status.pill == .unreachable
    }

    /// The banner's title.
    public static func title(serverName: String) -> String {
        "Can't reach \(serverName)"
    }

    /// The banner's message: the message the user wrote is kept and sends when the server is back.
    public static let message = "Your message will send when it's back."

    /// The actions, in the order they show.
    public static let actions: [OutageAction] = [.tryAgain, .continueInNewLocalChat]
}
