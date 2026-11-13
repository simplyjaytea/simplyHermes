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
    /// `version.json` on the standing release `app-update-feed` of the public repo. A fixed tag, so a later full
    /// release can't break the feed. No sign-in needed.
    public static let defaultFeedURL = URL(
        string: "https://github.com/simplyjaytea/simplyHermes/releases/download/app-update-feed/version.json")!
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
    public typealias FeedError = AppUpdateFeedError

    /// Automatic checks run at most this often after a check that worked.
    public static let interval: TimeInterval = 24 * 60 * 60
    /// After a failed check (offline, 404), the next automatic try waits this long instead of a full day.
    public static let retryInterval: TimeInterval = 60 * 60

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

    /// True when an automatic check should run now: 24 h after the last check that worked, and at least an hour
    /// after the last failed try. A clock that went back counts as elapsed.
    public static func isDue(lastCheck: Date?, lastAttempt: Date? = nil, now: Date) -> Bool {
        func elapsed(_ date: Date?, _ wait: TimeInterval) -> Bool {
            guard let date else { return true }
            let seconds = now.timeIntervalSince(date)
            return seconds < 0 || seconds >= wait
        }
        return elapsed(lastCheck, interval) && elapsed(lastAttempt, retryInterval)
    }

    /// Why a redirect hop is refused, or nil when it may be followed. `location` may be relative to `base`.
    public static func redirectFailure(location: String?, base: URL, allowedHosts: Set<String>) -> FeedError? {
        guard let location, let target = URL(string: location, relativeTo: base)?.absoluteURL else {
            return .malformed
        }
        do {
            try validate(target, allowedHosts: allowedHosts)
            return nil
        } catch {
            return error
        }
    }

    /// The feed to show in What's new at launch (row 73, proposals rev 2 §A), or nil. It shows only right after an
    /// update to the build the cached feed describes, and only when that feed has notes. A fresh install, the same
    /// build, a downgrade, or a feed for another build shows nothing.
    public static func whatsNew(installed: Int, lastSeen: Int?, cached: AppUpdateFeed?) -> AppUpdateFeed? {
        guard let lastSeen, installed > lastSeen, let feed = cached, feed.build == installed,
            !feed.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return feed
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
    static let lastAttemptKey = "appUpdate.lastAttempt"
    static let cachedFeedKey = "appUpdate.cachedFeed"
    static let lastSeenBuildKey = "appUpdate.lastSeenBuild"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// When a check last worked. Settings shows it as the last check time.
    public var lastCheck: Date? {
        get { defaults.object(forKey: Self.lastCheckKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastCheckKey) }
    }

    /// The highest build the user chose Later for.
    public var dismissedBuild: Int? {
        get { defaults.object(forKey: Self.dismissedBuildKey) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Self.dismissedBuildKey) }
    }

    /// When a check last ran, whether or not it worked. Spaces out retries after a failure.
    public var lastAttempt: Date? {
        get { defaults.object(forKey: Self.lastAttemptKey) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Self.lastAttemptKey) }
    }

    /// The last feed that was fetched and passed validation. Re-offered at launch so the banner survives a relaunch,
    /// and kept for the What's new sheet.
    public var cachedFeed: AppUpdateFeed? {
        get {
            defaults.data(forKey: Self.cachedFeedKey).flatMap {
                try? JSONDecoder().decode(AppUpdateFeed.self, from: $0)
            }
        }
        nonmutating set { defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Self.cachedFeedKey) }
    }

    /// The build that last ran, for the What's new sheet. Nil on a fresh install.
    public var lastSeenBuild: Int? {
        get { defaults.object(forKey: Self.lastSeenBuildKey) as? Int }
        nonmutating set { defaults.set(newValue, forKey: Self.lastSeenBuildKey) }
    }

    /// Why the last check failed. Nil after a check that worked.
    public var lastError: String? {
        get { defaults.string(forKey: Self.lastErrorKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.lastErrorKey) }
    }

    /// Forgets everything. UI tests start here.
    public func reset() {
        for key in [
            Self.lastCheckKey, Self.dismissedBuildKey, Self.lastErrorKey, Self.lastAttemptKey, Self.cachedFeedKey,
            Self.lastSeenBuildKey,
        ] {
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

    /// Runs a check. Without `force`, it fetches at most once every 24 hours, or an hour after a failed try.
    /// A failed check keeps the last good check time. It keeps the cached feed too (offline, a timeout or a 5xx says
    /// nothing about the release), except for ``AppUpdateFeedError/notPublished``: a 404 means the feed was
    /// withdrawn, so the remembered build is forgotten and the banner stops offering it.
    public func check(force: Bool = false) async -> AppUpdateResult {
        let time = now()
        guard force || AppUpdateRules.isDue(lastCheck: record.lastCheck, lastAttempt: record.lastAttempt, now: time)
        else { return .skipped }
        record.lastAttempt = time
        do {
            let data = try await fetch(config.feedURL)
            let feed = try AppUpdateRules.decode(data, allowedHosts: config.allowedHosts)
            record.lastCheck = time
            record.lastError = nil
            record.cachedFeed = feed
            return offerResult(feed)
        } catch let error as AppUpdateFeedError {
            return fail(error)
        } catch {
            return fail(.unreachable(error.localizedDescription))
        }
    }

    /// The cached feed's offer, for launch: nil when there is none, it is not newer, the user chose Later for it, or
    /// its link is no longer on the allow-list.
    public func cachedOffer() -> AppUpdateFeed? {
        guard let feed = record.cachedFeed,
            (try? AppUpdateRules.validate(feed.installURL, allowedHosts: config.allowedHosts)) != nil
        else { return nil }
        return AppUpdateRules.offer(feed, installedBuild: installedBuild, dismissedBuild: record.dismissedBuild)
    }

    private func offerResult(_ feed: AppUpdateFeed) -> AppUpdateResult {
        AppUpdateRules.offer(feed, installedBuild: installedBuild, dismissedBuild: record.dismissedBuild)
            .map(AppUpdateResult.available) ?? .upToDate
    }

    /// What's new for this launch, or nil. With nothing to show (a fresh install, the same build, no notes) the running
    /// build is stored at once. With notes to show it is not: ``markWhatsNewSeen()`` stores it when the sheet is
    /// dismissed, so notes the app couldn't show (another layout, another sheet up) come back at the next launch.
    public func pendingWhatsNew() -> AppUpdateFeed? {
        let feed = AppUpdateRules.whatsNew(
            installed: installedBuild, lastSeen: record.lastSeenBuild, cached: record.cachedFeed)
        if feed == nil { record.lastSeenBuild = installedBuild }
        return feed
    }

    /// The user saw What's new for this build (Done on the sheet). It doesn't come back for it.
    public func markWhatsNewSeen() {
        record.lastSeenBuild = installedBuild
    }

    /// Later: this build is not offered again, a higher one is.
    public func dismiss(_ feed: AppUpdateFeed) {
        record.dismissedBuild = max(record.dismissedBuild ?? 0, feed.build)
    }

    private func fail(_ error: AppUpdateFeedError) -> AppUpdateResult {
        if error == .notPublished { record.cachedFeed = nil }
        record.lastError = error.message
        return .failed(error)
    }

    /// Fetches over HTTPS on an ephemeral session: no cache, no cookies, no credentials. Every redirect hop must stay
    /// `https` on an allowed host (a refused hop is not followed), so must the final URL, and anything but HTTP 200
    /// is an error.
    public static func download(allowedHosts: Set<String>) -> Fetch {
        { url in
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            request.httpMethod = "GET"
            request.httpShouldHandleCookies = false
            let session = NetworkSessions.make(
                configuration: .ephemeral, delegate: RedirectGuard(allowedHosts: allowedHosts), delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            if let final = response.url { try AppUpdateRules.validate(final, allowedHosts: allowedHosts) }
            if let http = response as? HTTPURLResponse {
                // A hop the guard refused comes back as the redirect itself.
                if (300..<400).contains(http.statusCode), let final = response.url {
                    let location = http.value(forHTTPHeaderField: "Location")
                    let failure = AppUpdateRules.redirectFailure(
                        location: location, base: final, allowedHosts: allowedHosts)
                    throw failure ?? AppUpdateFeedError.httpStatus(http.statusCode)
                }
                if http.statusCode == 404 { throw AppUpdateFeedError.notPublished }
                if http.statusCode != 200 { throw AppUpdateFeedError.httpStatus(http.statusCode) }
            }
            return data
        }
    }
}

/// Refuses a redirect hop that leaves `https` or the allowed hosts. The refused redirect is returned as the response.
private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
    let allowedHosts: Set<String>

    init(allowedHosts: Set<String>) {
        self.allowedHosts = allowedHosts
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        let allowed = request.url.map { (try? AppUpdateRules.validate($0, allowedHosts: allowedHosts)) != nil } ?? false
        completionHandler(allowed ? request : nil)
    }
}

extension StringProtocol {
    fileprivate var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
