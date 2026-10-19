import Foundation

/// The tint a member's avatar takes, from its profile name (WP-43 spec, section 7).
public enum RoomAvatarTint {
    /// The hue in degrees, from Desktop's hash of the profile name. Nil for the default profile and for an empty name,
    /// which take violet.
    public static func hue(forProfile profile: String) -> Int? {
        guard !profile.isEmpty, profile != "default" else { return nil }
        var hash: UInt32 = 0
        for unit in profile.utf16 {
            hash = hash &* 31 &+ UInt32(unit)
        }
        return Int(hash % 360)
    }
}
