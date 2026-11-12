import Foundation
import Testing

@testable import HermesKit

struct WhatsNewTests {
    private let signulous = URL(string: "https://www.signulous.com/dashboard")!

    private func feed(build: Int, notes: String = "Message actions\nFaster search") -> AppUpdateFeed {
        AppUpdateFeed(version: "0.1.0-alpha.\(build)", build: build, installURL: signulous, notes: notes)
    }

    private func record() -> (AppUpdateRecord, UserDefaults) {
        let name = "WhatsNewTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return (AppUpdateRecord(defaults: defaults), defaults)
    }

    @Test func showsOnlyAfterAnUpdateToTheFeedsBuild() {
        #expect(AppUpdateRules.whatsNew(installed: 3, lastSeen: 2, cached: feed(build: 3)) != nil)
        #expect(
            AppUpdateRules.whatsNew(installed: 3, lastSeen: nil, cached: feed(build: 3)) == nil,
            "fresh install")
        #expect(
            AppUpdateRules.whatsNew(installed: 3, lastSeen: 3, cached: feed(build: 3)) == nil,
            "same build")
        #expect(
            AppUpdateRules.whatsNew(installed: 2, lastSeen: 3, cached: feed(build: 2)) == nil,
            "downgrade")
        #expect(
            AppUpdateRules.whatsNew(installed: 3, lastSeen: 2, cached: feed(build: 4)) == nil,
            "the feed is for another build")
        #expect(AppUpdateRules.whatsNew(installed: 3, lastSeen: 2, cached: nil) == nil, "no feed")
        #expect(
            AppUpdateRules.whatsNew(installed: 3, lastSeen: 2, cached: feed(build: 3, notes: " \n"))
                == nil, "notes missing")
    }

    @Test func theSheetShowsOncePerBuildAndAFreshInstallIsStoredSilently() {
        let (record, _) = record()
        let fresh = AppUpdateChecker(installedBuild: 2, record: record, fetch: { _ in Data() })
        #expect(fresh.whatsNewOnLaunch() == nil)
        #expect(record.lastSeenBuild == 2)

        record.cachedFeed = feed(build: 3)
        let updated = AppUpdateChecker(installedBuild: 3, record: record, fetch: { _ in Data() })
        #expect(updated.whatsNewOnLaunch()?.version == "0.1.0-alpha.3")
        #expect(updated.whatsNewOnLaunch() == nil, "not again on the next launch")
        #expect(record.lastSeenBuild == 3)
    }

    @Test func resetForgetsTheLastSeenBuild() {
        let (record, _) = record()
        record.lastSeenBuild = 5
        record.reset()
        #expect(record.lastSeenBuild == nil)
    }
}
