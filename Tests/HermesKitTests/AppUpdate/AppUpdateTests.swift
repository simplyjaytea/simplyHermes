import Foundation
import HermesKit
import Testing

@Suite struct AppUpdateRulesTests {
    private func json(
        build: Int = 3, url: String = "https://github.com/simplyjaytea/simplyHermes/releases/tag/v0.1.0-alpha.3"
    ) -> Data {
        Data(
            """
            {"version":"0.1.0-alpha.3","build":\(build),"releaseURL":"\(url)","notes":"\\nMessage actions\\nMore"}
            """.utf8)
    }

    @Test func decodesAValidFeed() throws {
        let feed = try AppUpdateRules.decode(json())
        #expect(feed.version == "0.1.0-alpha.3")
        #expect(feed.build == 3)
        #expect(feed.headline == "Message actions")
    }

    @Test func rejectsMalformedJSON() {
        #expect(throws: AppUpdateFeedError.malformed) { try AppUpdateRules.decode(Data("not json".utf8)) }
        #expect(throws: AppUpdateFeedError.malformed) { try AppUpdateRules.decode(Data(#"{"version":"1"}"#.utf8)) }
    }

    @Test func rejectsANonHTTPSLink() {
        #expect(throws: AppUpdateFeedError.insecureLink) {
            try AppUpdateRules.decode(json(url: "http://github.com/simplyjaytea/simplyHermes/releases"))
        }
    }

    @Test func rejectsALinkToAnotherHost() {
        #expect(throws: AppUpdateFeedError.untrustedHost("evil.example")) {
            try AppUpdateRules.decode(json(url: "https://evil.example/simplyHermes.ipa"))
        }
    }

    @Test func rejectsAZeroBuild() {
        #expect(throws: AppUpdateFeedError.invalidBuild) { try AppUpdateRules.decode(json(build: 0)) }
    }

    @Test func offersOnlyNewerBuilds() throws {
        let feed = try AppUpdateRules.decode(json(build: 3))
        #expect(AppUpdateRules.offer(feed, installedBuild: 2, dismissedBuild: nil) == feed)
        #expect(AppUpdateRules.offer(feed, installedBuild: 3, dismissedBuild: nil) == nil)
        #expect(AppUpdateRules.offer(feed, installedBuild: 4, dismissedBuild: nil) == nil)
    }

    @Test func laterHidesThatBuildButNotANewerOne() throws {
        let feed = try AppUpdateRules.decode(json(build: 3))
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

    @Test func theCommittedFeedIsValid() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("release/version.json"))
        let feed = try AppUpdateRules.decode(data)
        #expect(feed.releaseURL.absoluteString.hasPrefix("https://github.com/simplyjaytea/simplyHermes/releases"))
    }
}

@Suite struct AppUpdateCheckerTests {
    private static let feed = Data(
        #"{"version":"0.1.0-alpha.3","build":3,"releaseURL":"https://github.com/simplyjaytea/simplyHermes/releases","notes":"New"}"#
            .utf8)

    private final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
    }

    private final class Calls: @unchecked Sendable {
        var count = 0
    }

    private func makeDefaults() -> UserDefaults {
        let name = "AppUpdateCheckerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func checker(
        installed: Int = 2, defaults: UserDefaults, clock: Clock, calls: Calls, data: Data = feed, fails: Bool = false
    ) -> AppUpdateChecker {
        let fetch: AppUpdateChecker.Fetch = { url in
            calls.count += 1
            #expect(url == AppUpdateRules.feedURL)
            if fails { throw URLError(.notConnectedToInternet) }
            return data
        }
        return AppUpdateChecker(
            installedBuild: installed, record: AppUpdateRecord(defaults: defaults), now: { clock.now }, fetch: fetch)
    }

    @Test func offersANewerBuild() async {
        let result = await checker(defaults: makeDefaults(), clock: Clock(), calls: Calls()).check()
        guard case .available(let feed) = result else {
            Issue.record("Expected an update, got \(result)")
            return
        }
        #expect(feed.build == 3)
    }

    @Test func sameBuildIsUpToDate() async {
        let result = await checker(installed: 3, defaults: makeDefaults(), clock: Clock(), calls: Calls()).check()
        #expect(result == .upToDate)
    }

    @Test func throttlesAutomaticChecksToOncePerDay() async {
        let defaults = makeDefaults()
        let clock = Clock()
        let calls = Calls()
        let subject = checker(defaults: defaults, clock: clock, calls: calls)
        _ = await subject.check()
        #expect(await subject.check() == .skipped)
        #expect(calls.count == 1)
        clock.now = clock.now.addingTimeInterval(AppUpdateRules.interval)
        _ = await subject.check()
        #expect(calls.count == 2)
    }

    @Test func checkNowIgnoresTheThrottle() async {
        let calls = Calls()
        let subject = checker(defaults: makeDefaults(), clock: Clock(), calls: calls)
        _ = await subject.check()
        _ = await subject.check(force: true)
        #expect(calls.count == 2)
    }

    @Test func laterSurvivesANewCheckerOnTheSameDefaults() async {
        let defaults = makeDefaults()
        let first = checker(defaults: defaults, clock: Clock(), calls: Calls())
        guard case .available(let feed) = await first.check() else {
            Issue.record("Expected an update")
            return
        }
        first.dismiss(feed)
        // As after a relaunch: a new checker, the same stored choice.
        let second = checker(defaults: defaults, clock: Clock(), calls: Calls())
        #expect(await second.check(force: true) == .upToDate)
    }

    @Test func aNetworkFailureIsRecordedQuietly() async {
        let defaults = makeDefaults()
        let result = await checker(defaults: defaults, clock: Clock(), calls: Calls(), fails: true).check()
        guard case .failed(.unreachable) = result else {
            Issue.record("Expected a failure, got \(result)")
            return
        }
        #expect(AppUpdateRecord(defaults: defaults).lastError?.hasPrefix("Couldn't reach GitHub") == true)
    }

    @Test func aBadFeedIsRecordedAndAGoodOneClearsIt() async {
        let defaults = makeDefaults()
        let clock = Clock()
        let bad = await checker(defaults: defaults, clock: clock, calls: Calls(), data: Data("[]".utf8)).check()
        #expect(bad == .failed(.malformed))
        #expect(AppUpdateRecord(defaults: defaults).lastError != nil)
        _ = await checker(defaults: defaults, clock: clock, calls: Calls()).check(force: true)
        #expect(AppUpdateRecord(defaults: defaults).lastError == nil)
    }
}
