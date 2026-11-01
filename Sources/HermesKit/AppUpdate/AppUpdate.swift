import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The app's update feed, `release/version.json` on `main`. CI or the release owner bumps it after a release.
///
/// ```json
/// { "version": "0.1.0-alpha.2", "build": 2, "releaseURL": "https://github.com/…/releases/tag/v0.1.0-alpha.2",
///   "notes": "…" }
/// ```
///
/// This is about the iPhone app itself. The Hermes server's own update check is `HermesUpdateCheck`.
public struct AppUpdateFeed: Sendable, Equatable, Codable {
    /// Shown to the user, such as `0.1.0-alpha.3`.
    public var version: String
    /// Compared with the installed `CFBundleVersion`.
    public var build: Int
    /// The GitHub release page. The Update button opens it in Safari; nothing is downloaded by the app.
    public var releaseURL: URL
    /// Short release notes. The banner shows the first line.
    public var notes: String

    public init(version: String, build: Int, releaseURL: URL, notes: String) {
        self.version = version
        self.build = build
        self.releaseURL = releaseURL
        self.notes = notes
    }

    /// The first non-empty line of the notes, for the banner.
    public var headline: String {
        notes.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }
}

/// Why a feed was not used.
public enum AppUpdateFeedError: Error, Sendable, Equatable {
    /// Not JSON in the expected shape.
    case malformed
    /// The release link is not `https`.
    case insecureLink
    /// The release link points somewhere other than the allowed hosts.
    case untrustedHost(String)
    /// The build number is zero or negative.
    case invalidBuild
    /// The feed could not be fetched, with the reason.
    case unreachable(String)

    /// Plain words for Settings.
    public var message: String {
        switch self {
        case .malformed: "The update information could not be read."
        case .insecureLink: "The update link is not secure."
        case .untrustedHost(let host): "The update link points to \(host), which is not trusted."
        case .invalidBuild: "The update information has an invalid build number."
        case .unreachable(let reason): reason
        }
    }
}

/// Pure rules of the app update check: read the feed, check the link, decide if it is newer and if it is due.
public enum AppUpdateRules {
    /// Where the feed lives. The repository is public, so no sign-in is needed.
    public static let feedURL = URL(
        string: "https://raw.githubusercontent.com/simplyjaytea/simplyHermes/main/release/version.json")!
    /// Hosts the release link may point to. A changed feed cannot send the user anywhere else.
    public static let allowedHosts: Set<String> = ["github.com"]
    /// Automatic checks run at most this often.
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Decodes and checks a feed.
    public static func decode(_ data: Data) throws(AppUpdateFeedError) -> AppUpdateFeed {
        let feed: AppUpdateFeed
        do {
            feed = try JSONDecoder().decode(AppUpdateFeed.self, from: data)
        } catch {
            throw .malformed
        }
        guard feed.build > 0 else { throw .invalidBuild }
        guard feed.releaseURL.scheme?.lowercased() == "https" else { throw .insecureLink }
        let host = feed.releaseURL.host?.lowercased() ?? ""
        guard allowedHosts.contains(host) else { throw .untrustedHost(host) }
        return feed
    }

    /// The feed to offer, or nil: when it is not newer than the installed build, or the user chose Later for this
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

    /// The installed build number from `CFBundleVersion`. Zero when it is missing or not a number.
    public static func installedBuild(_ bundleVersion: String?) -> Int {
        bundleVersion.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
    }
}

/// What the user last saw of the update check. Kept in `UserDefaults`.
public struct AppUpdateRecord: @unchecked Sendable {
    static let lastCheckKey = "appUpdate.lastCheck"
    static let dismissedBuildKey = "appUpdate.dismissedBuild"
    static let lastErrorKey = "appUpdate.lastError"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When the feed was last fetched, successfully or not.
    public var lastCheck: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    /// The build the user chose Later for.
    public var dismissedBuild: Int? {
        get { defaults.object(forKey: Self.dismissedBuildKey) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Self.dismissedBuildKey) }
    }

    /// Why the last check failed, for Settings. Nil after a check that worked.
    public var lastError: String? {
        get { defaults.string(forKey: Self.lastErrorKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastErrorKey) }
    }

    /// Forgets everything, as a UI test starts.
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
    /// The installed build is current, or the user said Later to this one.
    case upToDate
    /// A newer build to offer.
    case available(AppUpdateFeed)
    /// The feed could not be used. Shown only in Settings, never as a popup.
    case failed(AppUpdateFeedError)
}

/// Fetches the feed and applies ``AppUpdateRules``. The fetch and the clock are injected, so tests need no network.
public struct AppUpdateChecker: Sendable {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    private let fetch: Fetch
    private let record: AppUpdateRecord
    private let installedBuild: Int
    private let now: @Sendable () -> Date

    public init(
        installedBuild: Int, record: AppUpdateRecord = AppUpdateRecord(),
        now: @escaping @Sendable () -> Date = Date.init,
        fetch: @escaping Fetch = AppUpdateChecker.download
    ) {
        self.installedBuild = installedBuild
        self.record = record
        self.now = now
        self.fetch = fetch
    }

    /// Runs a check. Without `force` it only fetches once a day.
    public func check(force: Bool = false) async -> AppUpdateResult {
        let time = now()
        guard force || AppUpdateRules.isDue(lastCheck: record.lastCheck, now: time) else { return .skipped }
        record.lastCheck = time
        let data: Data
        do {
            data = try await fetch(AppUpdateRules.feedURL)
        } catch {
            return fail(.unreachable("Couldn't reach GitHub: \(error.localizedDescription)"))
        }
        let feed: AppUpdateFeed
        do {
            feed = try AppUpdateRules.decode(data)
        } catch {
            return fail(error)
        }
        record.lastError = nil
        guard
            let offer = AppUpdateRules.offer(
                feed, installedBuild: installedBuild, dismissedBuild: record.dismissedBuild)
        else { return .upToDate }
        return .available(offer)
    }

    /// The user chose Later: this build is not offered again, a newer one is.
    public func dismiss(_ feed: AppUpdateFeed) {
        record.dismissedBuild = max(record.dismissedBuild ?? 0, feed.build)
    }

    private func fail(_ error: AppUpdateFeedError) -> AppUpdateResult {
        record.lastError = error.message
        return .failed(error)
    }

    /// Fetches over HTTPS without the local cache. Anything but HTTP 200 is an error.
    public static let download: Fetch = { url in
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
