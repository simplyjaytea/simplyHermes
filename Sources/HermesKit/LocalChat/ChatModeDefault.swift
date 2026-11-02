import Foundation

/// The mode new chats start in (WP-7). Settings sets it. It changes no chat that already exists: a chat keeps the
/// backend it was created with.
public enum ChatModeDefault {
    /// The `UserDefaults` key the default is stored under.
    public static let key = "chatModeDefault"

    /// The default in the app's standard defaults.
    public static var current: ChatMode { load(from: .standard) }

    /// The saved default, or ``ChatMode/online`` until the user picks local.
    public static func load(from defaults: UserDefaults) -> ChatMode {
        defaults.string(forKey: key).flatMap(ChatMode.init(rawValue:)) ?? .online
    }
}
