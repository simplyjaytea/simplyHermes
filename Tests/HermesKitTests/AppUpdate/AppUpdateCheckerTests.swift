import Foundation
import HermesKit
import Testing

private let signulous = "https://www.signulous.com/dashboard"

private func feedJSON(build: Int = 3, url: String = signulous, notes: String = "\\nMessage actions\\nMore") -> Data {
    Data(#"{"version":"0.1.0-alpha.3","build":\#(build),"installURL":"\#(url)","notes":"\#(notes)"}"#.utf8)
}

@Suite struct AppUpdateConfigTests {
    @Test func defaultsToTheLatestGitHubReleaseAndSignulous() {
        let config = AppUpdateConfig()
        #expect(
            config.feedURL.absoluteString
                == "https://github.com/simplyjaytea/simplyHermes/releases/download/app-update-feed/version.json")
        // The release-asset download redirects to these hosts, and release pages live on github.com.
        for host in ["github.com", "objects.githubusercontent.com", "release-assets.githubusercontent.com"] {
            #expect(config.allowedHosts.contains(host))
        }
        #expect(config.allowedHosts.contains("www.signulous.com"))
    }

    @Test func readsTheFeedAndInstallHostsFromInfoPlist() {
        let config = AppUpdateConfig(infoDictionary: [
            "HermesAppUpdateFeedURL": "https://example.org/feed/version.json",
            "HermesAppUpdateInstallHosts": ["Sign.Example.com"],
        ])
        #expect(config.feedURL.absoluteString == "https://example.org/feed/version.json")
        #expect(config.allowedHosts.contains("sign.example.com"))
        #expect(config.allowedHosts.contains("github.com"))
        #expect(!config.allowedHosts.contains("www.signulous.com"), "A configured host replaces the default")
    }

    @Test func acceptsSpaceSeparatedHosts() {
        let config = AppUpdateConfig(infoDictionary: ["HermesAppUpdateInstallHosts": "a.example b.example"])
        #expect(config.allowedHosts.isSuperset(of: ["a.example", "b.example"]))
    }

    @Test func fallsBackWhenTheConfigIsMissingOrInsecure() {
        let insecure = AppUpdateConfig(infoDictionary: ["HermesAppUpdateFeedURL": "http://example.org/version.json"])
        #expect(insecure.feedURL == AppUpdateConfig.defaultFeedURL)
        let empty = AppUpdateConfig(infoDictionary: ["HermesAppUpdateInstallHosts": "  "])
        #expect(empty == AppUpdateConfig())
    }
}

@Suite struct AppUpdateRulesTests {
    private let hosts = AppUpdateConfig().allowedHosts

    @Test func decodesAValidFeed() throws {
        let feed = try AppUpdateRules.decode(feedJSON(), allowedHosts: hosts)
        #expect(feed.version == "0.1.0-alpha.3")
        #expect(feed.build == 3)
        #expect(feed.installURL.absoluteString == signulous)
        #expect(feed.headline == "Message actions")
    }

    @Test func acceptsReleaseNotesAndMissingNotes() throws {
        let research = Data(
            #"{"version":"1","build":4,"minimumOS":"26.0","installURL":"\#(signulous)","releaseNotes":"Fixes"}"#.utf8)
        #expect(try AppUpdateRules.decode(research, allowedHosts: hosts).headline == "Fixes")
        let bare = Data(#"{"version":"1","build":4,"installURL":"\#(signulous)"}"#.utf8)
        #expect(try AppUpdateRules.decode(bare, allowedHosts: hosts).notes == "")
    }

    @Test func acceptsAGitHubReleaseAssetLink() throws {
        let url = "https://github.com/simplyjaytea/simplyHermes/releases/download/v0.1.0-alpha.3/simplyHermes.ipa"
        #expect(try AppUpdateRules.decode(feedJSON(url: url), allowedHosts: hosts).build == 3)
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: AppUpdateFeedError.malformed) {
            try AppUpdateRules.decode(Data("not json".utf8), allowedHosts: hosts)
        }
        #expect(throws: AppUpdateFeedError.malformed) {
            try AppUpdateRules.decode(Data(#"{"version":"1"}"#.utf8), allowedHosts: hosts)
        }
        #expect(throws: AppUpdateFeedError.malformed) {
            try AppUpdateRules.decode(Data(#"{"version":"1","build":"3","installURL":"x"}"#.utf8), allowedHosts: hosts)
        }
    }

    @Test func rejectsANonHTTPSLink() {
        #expect(throws: AppUpdateFeedError.insecureLink) {
            try AppUpdateRules.decode(feedJSON(url: "http://www.signulous.com/dashboard"), allowedHosts: hosts)
        }
        #expect(throws: AppUpdateFeedError.insecureLink) {
            try AppUpdateRules.decode(feedJSON(url: "itms-services://?action=download-manifest"), allowedHosts: hosts)
        }
    }

    @Test func rejectsAHostNotOnTheAllowList() {
        #expect(throws: AppUpdateFeedError.untrustedHost("evil.example")) {
            try AppUpdateRules.decode(feedJSON(url: "https://evil.example/simplyHermes.ipa"), allowedHosts: hosts)
        }
        // A look-alike subdomain is not the allowed host.
        #expect(throws: AppUpdateFeedError.untrustedHost("github.com.evil.example")) {
            try AppUpdateRules.decode(feedJSON(url: "https://github.com.evil.example/x"), allowedHosts: hosts)
        }
    }

    @Test func rejectsAZeroBuild() {
        #expect(throws: AppUpdateFeedError.invalidBuild) {
            try AppUpdateRules.decode(feedJSON(build: 0), allowedHosts: hosts)
        }
    }

    @Test func offersOnlyANewerBuild() throws {
        let feed = try AppUpdateRules.decode(feedJSON(build: 3), allowedHosts: hosts)
        #expect(AppUpdateRules.offer(feed, installedBuild: 2, dismissedBuild: nil) == feed, "newer")
        #expect(AppUpdateRules.offer(feed, installedBuild: 3, dismissedBuild: nil) == nil, "same")
        #expect(AppUpdateRules.offer(feed, installedBuild: 4, dismissedBuild: nil) == nil, "older")
    }

    @Test func laterHidesThatBuildButNotAHigherOne() throws {
        let feed = try AppUpdateRules.decode(feedJSON(build: 3), allowedHosts: hosts)
        #expect(AppUpdateRules.offer(feed, installedBuild: 1, dismissedBuild: 3) == nil)
        #expect(AppUpdateRules.offer(feed, installedBuild: 1, dismissedBuild: 2) == feed)
    }

    @Test func checksAreDueOncePerDay() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(AppUpdateRules.isDue(lastCheck: nil, now: start))
        #expect(!AppUpdateRules.isDue(lastCheck: start, now: start.addingTimeInterval(23 * 3600)))
        #expect(AppUpdateRules.isDue(lastCheck: start, now: start.addingTimeInterval(24 * 3600)))
        #expect(AppUpdateRules.isDue(lastCheck: start, now: start.addingTimeInterval(-60)), "A clock moved back is due")
    }

    @Test func readsTheInstalledBuild() {
        #expect(AppUpdateRules.installedBuild("2") == 2)
        #expect(AppUpdateRules.installedBuild(" 12 ") == 12)
        #expect(AppUpdateRules.installedBuild("1.2") == 0)
        #expect(AppUpdateRules.installedBuild(nil) == 0)
    }

    @Test func errorMessagesCompleteCouldntCheck() {
        #expect(AppUpdateFeedError.notPublished.message == "no release has update information yet.")
        #expect(AppUpdateFeedError.httpStatus(503).message.contains("503"))
    }
}

@Suite struct AppUpdateCheckerTests {
    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private final class Calls: @unchecked Sendable {
        var urls: [URL] = []
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppUpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func checker(
        installed: Int = 2, defaults: UserDefaults, clock: Clock = Clock(), calls: Calls = Calls(),
        result: @escaping @Sendable () throws -> Data = { feedJSON() }
    ) -> AppUpdateChecker {
        AppUpdateChecker(
            installedBuild: installed, record: AppUpdateRecord(defaults: defaults), now: { clock.now },
            fetch: { url in
                calls.urls.append(url)
                return try result()
            })
    }

    @Test func fetchesTheConfiguredFeedAndOffersANewerBuild() async {
        let calls = Calls()
        let result = await checker(defaults: makeDefaults(), calls: calls).check()
        #expect(calls.urls == [AppUpdateConfig.defaultFeedURL])
        guard case .available(let feed) = result else {
            Issue.record("Expected an update, got \(result)")
            return
        }
        #expect(feed.build == 3)
    }

    @Test func sameAndOlderBuildsAreUpToDate() async {
        #expect(await checker(installed: 3, defaults: makeDefaults()).check() == .upToDate)
        #expect(await checker(installed: 9, defaults: makeDefaults()).check() == .upToDate)
    }

    @Test func throttlesAutomaticChecksTo24Hours() async {
        let clock = Clock()
        let calls = Calls()
        let subject = checker(defaults: makeDefaults(), clock: clock, calls: calls)
        _ = await subject.check()
        clock.now = clock.now.addingTimeInterval(AppUpdateRules.interval - 1)
        #expect(await subject.check() == .skipped)
        #expect(calls.urls.count == 1)
        clock.now = clock.now.addingTimeInterval(1)
        _ = await subject.check()
        #expect(calls.urls.count == 2)
    }

    @Test func theThrottleHoldsAcrossARelaunch() async {
        let defaults = makeDefaults()
        let clock = Clock()
        let calls = Calls()
        _ = await checker(defaults: defaults, clock: clock, calls: calls).check()
        #expect(await checker(defaults: defaults, clock: clock, calls: calls).check() == .skipped)
        #expect(calls.urls.count == 1)
    }

    @Test func checkNowIgnoresTheThrottle() async {
        let calls = Calls()
        let subject = checker(defaults: makeDefaults(), calls: calls)
        _ = await subject.check()
        _ = await subject.check(force: true)
        #expect(calls.urls.count == 2)
    }

    @Test func laterStoresTheDismissedBuildAcrossARelaunch() async {
        let defaults = makeDefaults()
        let first = checker(defaults: defaults)
        guard case .available(let feed) = await first.check() else {
            Issue.record("Expected an update")
            return
        }
        first.dismiss(feed)
        #expect(AppUpdateRecord(defaults: defaults).dismissedBuild == 3)
        // As after a relaunch: a new checker on the same stored choice.
        #expect(await checker(defaults: defaults).check(force: true) == .upToDate)
        // A higher build comes back.
        let higher = await checker(defaults: defaults, result: { feedJSON(build: 4) }).check(force: true)
        #expect(higher != .upToDate)
        // Dismissing an older feed never lowers the stored build.
        first.dismiss(AppUpdateFeed(version: "old", build: 1, installURL: URL(string: signulous)!))
        #expect(AppUpdateRecord(defaults: defaults).dismissedBuild == 3)
    }

    @Test func aNetworkFailureIsRecordedForSettings() async {
        let defaults = makeDefaults()
        let result = await checker(defaults: defaults, result: { throw URLError(.notConnectedToInternet) }).check()
        guard case .failed(.unreachable) = result else {
            Issue.record("Expected a failure, got \(result)")
            return
        }
        #expect(AppUpdateRecord(defaults: defaults).lastError?.isEmpty == false)
        #expect(AppUpdateRecord(defaults: defaults).lastCheck != nil, "A failed check still counts for the throttle")
    }

    @Test func aMissingFeedSaysNothingIsPublished() async {
        let defaults = makeDefaults()
        let result = await checker(defaults: defaults, result: { throw AppUpdateFeedError.notPublished }).check()
        #expect(result == .failed(.notPublished))
        #expect(AppUpdateRecord(defaults: defaults).lastError == "no release has update information yet.")
    }

    @Test func aBadFeedIsRecordedAndAGoodOneClearsIt() async {
        let defaults = makeDefaults()
        let bad = await checker(defaults: defaults, result: { Data("[]".utf8) }).check()
        #expect(bad == .failed(.malformed))
        #expect(AppUpdateRecord(defaults: defaults).lastError != nil)
        _ = await checker(defaults: defaults).check(force: true)
        #expect(AppUpdateRecord(defaults: defaults).lastError == nil)
    }

    @Test func anUntrustedFeedIsNeverOffered() async {
        let result = await checker(defaults: makeDefaults(), result: { feedJSON(url: "https://evil.example/x") })
            .check()
        #expect(result == .failed(.untrustedHost("evil.example")))
    }
}
