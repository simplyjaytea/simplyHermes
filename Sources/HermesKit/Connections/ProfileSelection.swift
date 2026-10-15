import Foundation

/// The profiles of one server and which one the user chose, ready for a switcher menu.
///
/// `chosen == nil` follows the server's own active profile. A remembered choice that no longer exists on the server
/// (the bot was deleted or renamed) is dropped by ``resolve(profiles:stored:)``.
public struct ProfileSelection: Sendable, Equatable {
    /// Every profile on the server, in the server's order.
    public var profiles: [HermesProfile]
    /// The profile the user picked, or nil to follow the server.
    public var chosen: String?

    /// Creates a selection as is.
    public init(profiles: [HermesProfile] = [], chosen: String? = nil) {
        self.profiles = profiles
        self.chosen = chosen
    }

    /// Keeps `stored` only when the server still has a profile of that name.
    public static func resolve(profiles: [HermesProfile], stored: String?) -> ProfileSelection {
        let known = stored.flatMap { name in profiles.contains { $0.name == name } ? name : nil }
        return ProfileSelection(profiles: profiles, chosen: known)
    }

    /// The profile calls are scoped to: the chosen one, else the server's default profile.
    public var current: HermesProfile? {
        if let chosen { return profiles.first { $0.name == chosen } }
        return profiles.first { $0.isDefault == true }
    }

    /// The text for the header chip.
    public var label: String { Self.title(of: current) ?? chosen ?? "Default" }

    /// Menu rows: the name to show for each profile, and whether it is the current one.
    public var rows: [Row] {
        let currentName = current?.name
        return profiles.map {
            Row(name: $0.name, title: Self.title(of: $0) ?? $0.name, isCurrent: $0.name == currentName)
        }
    }

    /// One menu row.
    public struct Row: Sendable, Equatable, Identifiable {
        public var name: String
        public var title: String
        public var isCurrent: Bool
        public var id: String { name }
    }

    private static func title(of profile: HermesProfile?) -> String? {
        guard let profile else { return nil }
        if let display = profile.displayName?.trimmingCharacters(in: .whitespaces), !display.isEmpty { return display }
        return profile.name
    }
}
