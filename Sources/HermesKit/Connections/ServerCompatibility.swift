/// Is the server new enough for this app (WP-15, plan 2.9)?
///
/// Hermes git installs report `version: "unknown"`, so the check never reads `version`. It reads `release_date` and
/// `latest_config_version` from `/api/status` before connecting, and `info.desktop_contract` from the first
/// `session.create` or `session.activate`. The minimum is what the testbed pins (git `d97007c`).
public enum ServerCompatibility: Sendable, Equatable {
    /// New enough.
    case compatible
    /// Too old: show "Update your Hermes". `found` names what was too old, for the details line.
    case updateRequired(found: String)
    /// Newer protocol than this app knows. It still connects; the app suggests updating simplyHermes.
    case newerThanApp(contract: Int)

    /// Oldest `release_date` the app supports (`YYYY.M.D`).
    public static let minimumReleaseDate = "2026.9.24"
    /// Oldest `latest_config_version` (the config schema the server's code knows).
    public static let minimumConfigVersion = 50
    /// The `desktop_contract` this app speaks.
    public static let desktopContract = 8

    /// Checks `/api/status`. A missing field is not held against the server; the contract check covers it later.
    public static func check(_ status: ServerStatus) -> ServerCompatibility {
        if let date = status.releaseDate, isOlder(date, than: minimumReleaseDate) {
            return .updateRequired(found: "release \(date)")
        }
        if let config = status.latestConfigVersion, config < minimumConfigVersion {
            return .updateRequired(found: "config version \(config)")
        }
        return .compatible
    }

    /// Checks `info.desktop_contract` from a session result.
    public static func check(desktopContract contract: Int) -> ServerCompatibility {
        if contract < desktopContract { return .updateRequired(found: "desktop contract \(contract)") }
        if contract > desktopContract { return .newerThanApp(contract: contract) }
        return .compatible
    }

    /// Checks a session result's raw `desktop_contract`. Nil or a non-number is not held against the server.
    public static func check(desktopContract raw: JSONValue?) -> ServerCompatibility {
        switch raw {
        case .int(let contract)?: check(desktopContract: contract)
        case .string(let text)?: Int(text).map { check(desktopContract: $0) } ?? .compatible
        default: .compatible
        }
    }

    /// True when release `date` is before `minimum`. False when either has another shape.
    static func isOlder(_ date: String, than minimum: String) -> Bool {
        guard let found = releaseDate(date), let floor = releaseDate(minimum) else { return false }
        return found.lexicographicallyPrecedes(floor)
    }

    /// `2026.9.24` as comparable numbers. Nil when the text has another shape.
    static func releaseDate(_ text: String) -> [Int]? {
        let parts = text.split(separator: ".").map { Int($0) }
        guard parts.count == 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }

    /// True when the app can connect.
    public var allowsConnecting: Bool {
        if case .updateRequired = self { return false }
        return true
    }
}
