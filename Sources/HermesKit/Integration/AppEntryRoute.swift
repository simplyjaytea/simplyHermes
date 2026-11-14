import Foundation

/// What the app shows at its root: the Welcome screen, which only offers ways to add a server, or the shell with the
/// chat list. Welcome must never hide chats the user already has: local chats live on this iPhone and need no server,
/// so with no server saved but local chats on disk, the shell stays (iOS run 43495829201 showed a relaunch landing on
/// Welcome with the saved local chat out of reach; removing the last server did the same).
public enum AppEntryRoute: Sendable, Equatable {
    /// Not known yet: the local chat store is still being read. Show neither, so Welcome doesn't flash.
    case loading
    case welcome
    case shell

    /// - Parameters:
    ///   - hasServers: at least one server is saved.
    ///   - skipsOnboarding: a UI test or preview asked for the shell (`-HermesOnboarding skip`).
    ///   - hasLocalChats: whether any local chat is saved; nil while that is still being read.
    public static func decide(hasServers: Bool, skipsOnboarding: Bool, hasLocalChats: Bool?) -> AppEntryRoute {
        if hasServers || skipsOnboarding { return .shell }
        switch hasLocalChats {
        case nil: return .loading
        case true?: return .shell
        case false?: return .welcome
        }
    }
}
