import Foundation

/// The Settings switch that turns every on-device feature off: offline chat, chat titles, summaries and prompt polish
/// (plan WP-65b). It is on by default. The switch lives in `UserDefaults`, so the Settings screen
/// (`@AppStorage(OnDeviceSettings.key)`) and the on-device executors read the same value.
///
/// `@unchecked Sendable`: `UserDefaults` is documented as thread safe, but Foundation on Linux does not mark it
/// `Sendable`.
public struct OnDeviceSettings: @unchecked Sendable {
    /// `UserDefaults` key for the switch.
    public static let key = "onDeviceEnabled"

    private let defaults: UserDefaults

    /// Reads and writes the switch in `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// True when on-device features may run. A missing value counts as on.
    public var isEnabled: Bool {
        get { defaults.object(forKey: Self.key) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}
