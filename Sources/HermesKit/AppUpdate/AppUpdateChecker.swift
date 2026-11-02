import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// "App update" is the iPhone app itself: a newer simplyHermes build. The Hermes *server* update is a different thing
// (`HermesUpdateCheck`). Keep the two names apart in code and in the UI.

/// Where the app update feed lives and where its install link may point. The app reads it from its Info.plist
/// (`HermesAppUpdateFeedURL`, `HermesAppUpdateInstallHosts`), so the feed and the Signulous host are configuration,
/// not code.
public struct AppUpdateConfig: Sendable, Equatable {
    /// `version.json` on the latest GitHub release of the public repo. No sign-in needed.
    public static let defaultFeedURL = URL(
        string: "https://github.com/simplyjaytea/simplyHermes/releases/latest/download/version.json")!
    /// Hosts the feed redirect and GitHub release assets resolve to.
    public static let gitHubHosts: Set<String> = [
        "github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com",
    ]
    /// The Signulous dashboard, used when the Info.plist names no install host.
    public static let defaultInstallHosts: Set<String> = ["www.signulous.com", "signulous.com"]

    static let feedURLKey = "HermesAppUpdateFeedURL"
    static let installHostsKey = "HermesAppUpdateInstallHosts"

    /// The feed to fetch. Always `https`.
    public let feedURL: URL
    /// Hosts the feed may redirect to and the install link may point to: GitHub's plus the configured install hosts.
    public let allowedHosts: Set<String>

    public init(feedURL: URL = Self.defaultFeedURL, installHosts: Set<String> = Self.defaultInstallHosts) {
        self.feedURL = AppUpdateRules.isSecure(feedURL) ? feedURL : Self.defaultFeedURL
        allowedHosts = Self.gitHubHosts.union(installHosts.map { $0.lowercased() })
    }

    /// Reads the Info.plist keys. A missing, empty or non-`https` value falls back to the default.
    /// `HermesAppUpdateInstallHosts` is an array of host names or one space-separated string.
    public init(infoDictionary: [String: Any]) {
        let feed = (infoDictionary[Self.feedURLKey] as? String).flatMap { URL(string: $0.trimmed) }
        let raw: [String] =
            (infoDictionary[Self.installHostsKey] as? [String])
            ?? (infoDictionary[Self.installHostsKey] as? String)?.split(separator: " ").map(String.init) ?? []
        let hosts = Set(raw.map(\.trimmed).filter { !$0.isEmpty })
        self.init(feedURL: feed ?? Self.defaultFeedURL, installHosts: hosts.isEmpty ? Self.defaultInstallHosts : hosts)
    }
}

/// The app update feed, `version.json`:
///
/// ```json
/// { "version": "0.1.0-alpha.3", "build": 3, "installURL": "https://www.signulous.com/dashboard", "notes": "…" }
/// ```
public struct AppUpdateFeed: Sendable, Equatable, Codable {
    /// Shown to the user, such as `0.1.0-alpha.3`.
    public var version: String
    /// Compared with the installed `CFBundleVersion`. The marketing version is never used for ordering.
    public var build: Int
    /// Where Update sends the user, in Safari. The app never downloads or installs anything.
    public var installURL: URL
    /// Short release notes. The banner shows the first line.
    public var notes: String

    public init(version: String, build: Int, installURL: URL, notes: String = "") {
        self.version = version
        self.build = build
        self.installURL = installURL
        self.notes = notes
    }

    private enum CodingKeys: String, CodingKey {
        case version, build, installURL, notes, releaseNotes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        build = try container.decode(Int.self, forKey: .build)
        installURL = try container.decode(URL.self, forKey: .installURL)
        notes =
            try container.decodeIfPresent(String.self, forKey: .notes)
            ?? container.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(build, forKey: .build)
        try container.encode(installURL, forKey: .installURL)
        try container.encode(notes, forKey: .notes)
    }

    /// The first non-empty line of the notes, for the banner.
    public var headline: String {
        notes.split(whereSeparator: \.isNewline).map(\.trimmed).first { !$0.isEmpty } ?? ""
    }
}

/// Why a check did not produce a usable feed. ``message`` completes "Couldn't check: …" in Settings.
public enum AppUpdateFeedError: Error, Sendable, Equatable {
    /// Not JSON in the expected shape.
    case malformed
    /// The install link or the feed redirect is not `https`.
    case insecureLink
    /// The install link or the feed redirect points to a host that is not allowed.
    case untrustedHost(String)
    /// The build number is zero or negative.
    case invalidBuild
    /// The feed answered 404: no release carries `version.json` yet.
    case notPublished
    /// The feed answered with another HTTP status.
    case httpStatus(Int)
    /// The feed could not be reached, with the system's reason.
    case unreachable(String)

    public var message: String {
        switch self {
        case .malformed: "the update information could not be read."
        case .insecureLink: "the update link is not secure."
        case .untrustedHost(let host): "the update link points to \(host), which isn't trusted."
        case .invalidBuild: "the update information has an invalid build number."
        case .notPublished: "no release has update information yet."
        case .httpStatus(let code): "the update server answered with error \(code)."
        case .unreachable(let reason): reason
        }
    }
}

/// The pure rules: read the feed, check its link, decide whether it is newer and whether a check is due.
public enum AppUpdateRules {
    /// Automatic checks run at most this often.
    public static let interval: TimeInterval = 24 * 60 * 60

    static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
    }

    /// Checks that a URL is `https` on an allowed host.
    public static func validate(_ url: URL, allowedHosts: Set<String>) throws(AppUpdateFeedError) {
        guard isSecure(url) else { throw .insecureLink }
        let host = url.host?.lowercased() ?? ""
        guard allowedHosts.contains(host) else { throw .untrustedHost(host) }
    }

    /// Decodes a feed and checks its build and install link.
    public static func decode(_ data: Data, allowedHosts: Set<String>) throws(AppUpdateFeedError) -> AppUpdateFeed {
        let feed: AppUpdateFeed
        do {
            feed = try JSONDecoder().decode(AppUpdateFeed.self, from: data)
        } catch {
            throw .malformed
        }
        guard feed.build > 0 else { throw .invalidBuild }
        try validate(feed.installURL, allowedHosts: allowedHosts)
        return feed
    }

    /// The feed to offer, or nil when it is not newer than the installed build, or the user chose Later for this
    /// build or a newer one.
    public static func offer(_ feed: AppUpdateFeed, installedBuild: Int, dismissedBuild: Int?) -> AppUpdateFeed? {
        guard feed.build > installedBuild else { return nil }
        if let dismissedBuild, dismissedBuild >= feed.build { return nil }
        return feed
    }

    /// True when an automatic check should run now. A clock that went back counts as due.
    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed < 0 || elapsed >= interval
    }

    /// The installed build from `CFBundleVersion`. Zero when it is missing or not a whole number.
    public static func installedBuild(_ bundleVersion: String?) -> Int {
        bundleVersion.flatMap { Int($0.trimmed) } ?? 0
    }
}

/// What the app update check remembers, in `UserDefaults`.
public struct AppUpdateRecord: @unchecked Sendable {
    static let lastCheckKey = "appUpdate.lastCheck"
    static let dismissedBuildKey = "appUpdate.dismissedBuild"
    static let lastErrorKey = "appUpdate.lastError"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When the feed was last fetched, whether or not that worked.
    public var lastCheck: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    /// The highest build the user chose Later for.
    public var dismissedBuild: Int? {
        get { defaults.object(forKey: Self.dismissedBuildKey) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Self.dismissedBuildKey) }
    }

    /// Why the last check failed. Nil after a check that worked.
    public var lastError: String? {
        get { defaults.string(forKey: Self.lastErrorKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastErrorKey) }
    }

    /// Forgets everything. UI tests start here.
    public func reset() {
        for key in [Self.lastCheckKey, Self.dismissedBuildKey, Self.lastErrorKey] {
            defaults.removeObject(forKey: key)
        }
    }
}

/// The result of one check.
public enum AppUpdateResult: Sendable, Equatable {
    /// Not due yet; nothing was fetched.
    case skipped
    /// The installed build is current, or the user chose Later for this one.
    case upToDate
    /// A newer build to offer.
    case available(AppUpdateFeed)
    /// The feed could not be used. Shown only in Settings, never as a popup.
    case failed(AppUpdateFeedError)
}

/// Fetches the feed and applies ``AppUpdateRules``. The fetch and the clock are injected, so tests need no network.
public struct AppUpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    public let config: AppUpdateConfig
    private let fetch: Fetch
    private let record: AppUpdateRecord
    private let installedBuild: Int
    private let now: @Sendable () -> Date

    public init(
        installedBuild: Int, config: AppUpdateConfig = AppUpdateConfig(), record: AppUpdateRecord = AppUpdateRecord(),
        now: @escaping @Sendable () -> Date = Date.init, fetch: Fetch? = nil
    ) {
        self.installedBuild = installedBuild
        self.config = config
        self.record = record
        self.now = now
        self.fetch = fetch ?? Self.download(allowedHosts: config.allowedHosts)
    }

    /// Runs a check. Without `force`, it fetches at most once every 24 hours.
    public func check(force: Bool = false) async -> AppUpdateResult {
        let time = now()
        guard force || AppUpdateRules.isDue(lastCheck: record.lastCheck, now: time) else { return .skipped }
        record.lastCheck = time
        do {
            let data = try await fetch(config.feedURL)
            let feed = try AppUpdateRules.decode(data, allowedHosts: config.allowedHosts)
            record.lastError = nil
            let offer = AppUpdateRules.offer(
                feed, installedBuild: installedBuild, dismissedBuild: record.dismissedBuild)
            return offer.map(AppUpdateResult.available) ?? .upToDate
        } catch let error as AppUpdateFeedError {
            return fail(error)
        } catch {
            return fail(.unreachable(error.localizedDescription))
        }
    }

    /// Later: this build is not offered again, a higher one is.
    public func dismiss(_ feed: AppUpdateFeed) {
        record.dismissedBuild = max(record.dismissedBuild ?? 0, feed.build)
    }

    private func fail(_ error: AppUpdateFeedError) -> AppUpdateResult {
        record.lastError = error.message
        return .failed(error)
    }

    /// Fetches over HTTPS without the local cache or credentials. The final URL after redirects must still be on an
    /// allowed host, and anything but HTTP 200 is an error.
    public static func download(allowedHosts: Set<String>) -> Fetch {
        { url in
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            request.httpShouldHandleCookies = false
            let (data, response) = try await URLSession.shared.data(for: request)
            if let final = response.url { try AppUpdateRules.validate(final, allowedHosts: allowedHosts) }
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 404 { throw AppUpdateFeedError.notPublished }
                if http.statusCode != 200 { throw AppUpdateFeedError.httpStatus(http.statusCode) }
            }
            return data
        }
    }
}

extension StringProtocol {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
