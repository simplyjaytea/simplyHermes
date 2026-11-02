import Foundation

/// The profile a chat is pinned to at its first attach.
///
/// The client's active profile is nil while the server's default is in use. A chat that pinned nil would follow
/// whatever profile became active later, such as another bot, because the client fills in nil. So a pin names the
/// default profile. The app's own roster names it "default" too (``BotClient``).
public enum ProfilePin {
    /// The name of the server's default profile.
    public static let defaultProfile = "default"

    /// The profile a chat pins to, given the client's active profile at attach time.
    public static func resolve(activeProfile: String?) -> String {
        activeProfile ?? defaultProfile
    }
}
