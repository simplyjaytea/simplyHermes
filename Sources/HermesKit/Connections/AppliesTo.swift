import Foundation

/// The profile a settings page applies its edits to (WP-41).
///
/// The default follows the server's active profile. Picking another profile edits that profile while the active one
/// stays put. A choice does not outlive the server or the active profile it was made under: ``AppliesToState`` resets
/// it. Pure rules, so the selector in HermesUI and every settings page share one definition. Settings writes that use
/// the choice wait for WP-53.
public enum AppliesTo: Sendable, Equatable {
    /// Follows the server's active profile. The default.
    case activeProfile
    /// Another profile of the server, picked in the selector.
    case profile(String)

    /// The selector is shown only when the server has at least two profiles.
    public static func isShown(for profiles: [HermesProfile]) -> Bool {
        profiles.count >= 2
    }

    /// The choice as it applies now. A name the server no longer has, or the active profile itself, means
    /// ``activeProfile``.
    public func normalized(in profiles: [HermesProfile], active: String?) -> AppliesTo {
        guard case .profile(let name) = self, name != active, profiles.contains(where: { $0.name == name }) else {
            return .activeProfile
        }
        return .profile(name)
    }

    /// The profile the settings calls go to. A stale name falls back to the active profile.
    public func target(in profiles: [HermesProfile], active: String?) -> String? {
        switch normalized(in: profiles, active: active) {
        case .activeProfile: active
        case .profile(let name): name
        }
    }

    /// The text of the selector's chip: "Active profile", or the title of the picked profile.
    public func chipTitle(in profiles: [HermesProfile], active: String?) -> String {
        switch normalized(in: profiles, active: active) {
        case .activeProfile:
            return "Active profile"
        case .profile(let name):
            return ProfileSelection.title(of: profiles.first { $0.name == name }) ?? name
        }
    }

    /// The rows of the selector menu: following the active profile first, then each other profile in the server's order.
    public func options(in profiles: [HermesProfile], active: String?) -> [AppliesToOption] {
        let current = normalized(in: profiles, active: active)
        let activeName = profiles.first { $0.name == active }.flatMap { ProfileSelection.title(of: $0) } ?? active
        var rows = [
            AppliesToOption(
                choice: .activeProfile, title: "Follows the active profile", detail: activeName,
                isSelected: current == .activeProfile)
        ]
        for profile in profiles where profile.name != active {
            let choice = AppliesTo.profile(profile.name)
            rows.append(
                AppliesToOption(
                    choice: choice, title: ProfileSelection.title(of: profile) ?? profile.name, detail: nil,
                    isSelected: current == choice))
        }
        return rows
    }
}

/// The "Applies to" choice and the server and active profile it was made under (WP-41).
///
/// A change of either server or active profile resets the choice to following, so an edit never lands on a profile the
/// user picked under another server or another default. The first observation only records the key.
public struct AppliesToState: Sendable, Equatable {
    /// The choice as the user made it. ``choice(in:)`` gives the one that applies now.
    public private(set) var stored: AppliesTo = .activeProfile
    /// The server and active profile the choice was made under. Nil until the first observation.
    private var key: Key?

    /// Creates the state with the default choice, which follows the active profile.
    public init() {}

    /// Records the server and the active profile now in effect. A change of either resets the choice to following.
    public mutating func observe(server: UUID?, active: String?) {
        let current = Key(server: server, active: active)
        if let key, key != current { stored = .activeProfile }
        key = current
    }

    /// Picks `choice` against the profiles now listed. Picking the active profile means following it.
    public mutating func pick(_ choice: AppliesTo, in profiles: [HermesProfile]) {
        stored = choice.normalized(in: profiles, active: key?.active)
    }

    /// The choice that applies now. A name the server no longer lists, or the active profile itself, reads as following.
    public func choice(in profiles: [HermesProfile]) -> AppliesTo {
        stored.normalized(in: profiles, active: key?.active)
    }

    /// The server and the active profile a choice was made under.
    private struct Key: Equatable, Sendable {
        var server: UUID?
        var active: String?
    }
}

/// One row of the "Applies to" menu.
public struct AppliesToOption: Sendable, Equatable, Identifiable {
    /// The choice the row makes.
    public var choice: AppliesTo
    /// The row's text.
    public var title: String
    /// A second line, such as the name of the active profile.
    public var detail: String?
    /// True for the choice in effect.
    public var isSelected: Bool

    /// Creates a row.
    public init(choice: AppliesTo, title: String, detail: String?, isSelected: Bool) {
        self.choice = choice
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
    }

    /// Identity for lists: unique per choice.
    public var id: String {
        switch choice {
        case .activeProfile: "active"
        case .profile(let name): "profile:" + name
        }
    }
}
