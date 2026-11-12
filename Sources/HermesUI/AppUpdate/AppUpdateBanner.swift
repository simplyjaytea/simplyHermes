#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI
    import UIKit

    /// App update: whether a newer simplyHermes build is out. This is the iPhone app, not the Hermes server
    /// (`HermesUpdateCheck`). It checks the feed from the Info.plist at most once a day, at launch and when the app
    /// comes back, and offers the install link. It never downloads, installs or opens anything by itself.
    @MainActor @Observable
    public final class AppUpdateModel {
        /// One model for the banner and Settings, so Later in one place hides the other.
        public static let shared = AppUpdateModel()

        /// The build to offer, or nil.
        public private(set) var available: AppUpdateFeed?
        public private(set) var isChecking = false
        /// Why the last check failed, for Settings.
        public private(set) var lastError: String?
        public private(set) var lastCheck: Date?
        /// Debug builds with `-HermesAppUpdateStubOpen YES` record the link here instead of opening Safari.
        public private(set) var openedURL: URL?

        @ObservationIgnored private let checker: AppUpdateChecker
        @ObservationIgnored private let record: AppUpdateRecord
        @ObservationIgnored private let stubsOpening: Bool

        public let installedVersion: String
        public let installedBuild: Int

        init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
            let build = AppUpdateRules.installedBuild(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            installedBuild = build
            installedVersion = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
            let record = AppUpdateRecord(defaults: defaults)
            self.record = record
            var fetch: AppUpdateChecker.Fetch?
            var stubs = false
            #if DEBUG
                // UI tests: a stub feed on the command line, a fresh record, and no Safari.
                if defaults.bool(forKey: "HermesAppUpdateReset") { record.reset() }
                // Hex, because a launch argument that looks like a property list would not arrive as a string.
                if let hex = defaults.string(forKey: "HermesAppUpdateFeedHex"), let data = Self.data(hex: hex) {
                    fetch = { _ in data }
                }
                stubs = defaults.bool(forKey: "HermesAppUpdateStubOpen")
            #endif
            stubsOpening = stubs
            checker = AppUpdateChecker(
                installedBuild: build, config: AppUpdateConfig(infoDictionary: bundle.infoDictionary ?? [:]),
                record: record, fetch: fetch)
            lastError = record.lastError
            lastCheck = record.lastCheck
            // A relaunch within 24 h skips the fetch, so offer the last good feed again (Later still applies).
            available = checker.cachedOffer()
        }

        #if DEBUG
            private static func data(hex: String) -> Data? {
                let digits = Array(hex.utf8)
                guard digits.count.isMultiple(of: 2) else { return nil }
                var bytes: [UInt8] = []
                bytes.reserveCapacity(digits.count / 2)
                for index in stride(from: 0, to: digits.count, by: 2) {
                    guard let pair = String(bytes: digits[index...index + 1], encoding: .utf8),
                        let byte = UInt8(pair, radix: 16)
                    else { return nil }
                    bytes.append(byte)
                }
                return Data(bytes)
            }
        #endif

        /// The automatic check, at launch and on return to the foreground: at most once every 24 hours.
        public func checkIfDue() async {
            await run(force: false)
        }

        /// Settings › Check for updates.
        public func checkNow() async {
            await run(force: true)
        }

        private func run(force: Bool) async {
            guard !isChecking else { return }
            isChecking = true
            defer { isChecking = false }
            let result = await checker.check(force: force)
            lastCheck = record.lastCheck
            lastError = record.lastError
            switch result {
            case .available(let feed): available = feed
            case .upToDate: available = nil
            // A failed check offers what is still cached: offline keeps the banner, a withdrawn feed clears it.
            case .skipped, .failed: available = checker.cachedOffer()
            }
        }

        /// Later: hides this build until a higher one is out.
        public func dismiss() {
            guard let available else { return }
            checker.dismiss(available)
            self.available = nil
        }

        /// Update: opens the install link in Safari.
        public func openInstallPage() {
            guard let url = available?.installURL else { return }
            if stubsOpening {
                openedURL = url
            } else {
                UIApplication.shared.open(url)
            }
        }
    }

    /// The app update banner at the top of the Chats list: "simplyHermes {version} is available." with Update and
    /// Later. It is absent when there is nothing to offer, and a failed check never shows here.
    public struct AppUpdateBanner: View {
        @Bindable private var model: AppUpdateModel
        @Environment(\.hermesPalette) private var palette

        public init(model: AppUpdateModel = .shared) {
            self.model = model
        }

        public var body: some View {
            VStack(spacing: 0) {
                // Always present, so the launch check runs while there is nothing to show yet.
                Color.clear.frame(height: 0)
                if let feed = model.available {
                    content(feed)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.available)
            .task { await model.checkIfDue() }
        }

        private func content(_ feed: AppUpdateFeed) -> some View {
            VStack(alignment: .leading, spacing: 10) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("simplyHermes \(feed.version) is available.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                        if !feed.headline.isEmpty {
                            Text(feed.headline)
                                .font(.footnote)
                                .foregroundStyle(palette.primaryText)
                                .lineLimit(3)
                        }
                    }
                } icon: {
                    Image(systemName: "arrow.down.app")
                        .foregroundStyle(palette.accent)
                        .accessibilityHidden(true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
                if let opened = model.openedURL {
                    Text(opened.absoluteString)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("appUpdate.opened")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("App update")
            .accessibilityIdentifier("appUpdate.banner")
        }

        @ViewBuilder private var buttons: some View {
            Button("Update") { model.openInstallPage() }
                .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                .accessibilityHint("Opens the install page in Safari")
                .accessibilityIdentifier("appUpdate.update")
            Button("Later") { model.dismiss() }
                .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                .accessibilityHint("Hides this app update until a newer build is out")
                .accessibilityIdentifier("appUpdate.later")
        }
    }

    /// Settings › About: the installed version, Check for updates, the last check time, and why it failed.
    public struct AppUpdateSettingsSection: View {
        @Bindable private var model: AppUpdateModel
        @Environment(\.hermesPalette) private var palette

        public init(model: AppUpdateModel = .shared) {
            self.model = model
        }

        public var body: some View {
            Section {
                LabeledContent("App version", value: "\(model.installedVersion) (\(model.installedBuild))")
                    .accessibilityIdentifier("settings.appVersion")
                Button {
                    Task { await model.checkNow() }
                } label: {
                    HStack {
                        Text("Check for updates")
                        Spacer()
                        if model.isChecking { ProgressView() }
                    }
                }
                .disabled(model.isChecking)
                .accessibilityHint("Checks for a newer simplyHermes app build")
                .accessibilityIdentifier("settings.checkForAppUpdates")
                LabeledContent("Last checked", value: lastChecked)
                    .accessibilityIdentifier("settings.appUpdateLastCheck")
                if let feed = model.available {
                    Button("Install \(feed.version) (\(String(feed.build)))") { model.openInstallPage() }
                        .accessibilityIdentifier("settings.installAppUpdate")
                }
                if let lastError = model.lastError {
                    Text("Couldn't check: \(lastError)")
                        .font(.footnote)
                        .foregroundStyle(palette.secondaryText)
                        .accessibilityIdentifier("settings.appUpdateError")
                }
            } header: {
                Text("About")
            } footer: {
                Text(
                    "App update checks for a newer simplyHermes build once a day. You install it the same way as this one."
                )
            }
            .listRowBackground(palette.card)
        }

        private var lastChecked: String {
            model.lastCheck?.formatted(date: .abbreviated, time: .shortened) ?? "Never"
        }
    }
#endif
