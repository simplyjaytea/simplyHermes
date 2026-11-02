import Foundation

/// The two ways to start a chat, offered by a long press on New chat.
public enum NewChatChoice: Sendable, Equatable, CaseIterable {
    /// A chat the Hermes server answers.
    case online
    /// A chat a model on this iPhone answers.
    case local

    /// The mode the chat starts in.
    public var mode: ChatMode {
        switch self {
        case .online: .online
        case .local: .local
        }
    }

    /// The menu title.
    public var title: String {
        switch self {
        case .online: "New Online chat"
        case .local: "New Local chat"
        }
    }

    /// The menu title with the model that would answer. A Local choice names the model only when one is ready, so the
    /// menu never implies a model that can't answer.
    public func menuTitle(localModelName: String?) -> String {
        switch self {
        case .online:
            return title
        case .local:
            guard let localModelName, !localModelName.isEmpty else { return title }
            return "\(title) · \(localModelName)"
        }
    }

    /// The menu symbol: the same one the chat's pill uses for its kind (UX spec §1.2).
    public var symbol: String {
        switch self {
        case .online: "point.3.connected.trianglepath.dotted"
        case .local: "iphone"
        }
    }
}
