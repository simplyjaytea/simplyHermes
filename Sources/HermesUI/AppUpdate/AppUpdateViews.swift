#if canImport(UIKit)
    import HermesKit
    import Observation
    import SwiftUI
    import UIKit

    /// Whether a newer simplyHermes build is out (the app itself, not the Hermes server). It checks
    /// `release/version.json` at most once a day, on launch and when the app comes back, and offers the GitHub release
    /// page. It never downloads or installs anything: the user signs and installs the new build themselves.
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
        /// Debug builds with `-HermesUpdateStubOpen YES` record the link here instead of opening Safari.
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
            var fetch = AppUpdateChecker.download
            var stubs = false
            #if DEBUG
                // UI tests: a fake feed passed on the command line, a fresh record, and no Safari.
                if defaults.bool(forKey: "HermesUpdateReset") { record.reset() }
                // Hex, because a launch argument that looks like a property list would not arrive as a string.
                if let hex = defaults.string(forKey: "HermesUpdateFeedHex"), let data = Self.data(hex: hex) {
                    fetch = { _ in data }
                }
                stubs = defaults.bool(forKey: "HermesUpdateStubOpen")
            #endif
            stubsOpening = stubs
            checker = AppUpdateChecker(installedBuild: build, record: record, fetch: fetch)
            lastError = record.lastError
            lastCheck = record.lastCheck
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

        /// The automatic check: at most once a day.
        public func checkIfDue() async {
            await run(force: false)
        }

        /// Settings > Check for updates.
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
            case .skipped, .failed: break
            }
        }

        /// Later: hides this build until a newer one is out.
        public func dismiss() {
            guard let available else { return }
            checker.dismiss(available)
            self.available = nil
        }

        /// Update: opens the release page in Safari.
        public func openRelease() {
            guard let url = available?.releaseURL else { return }
            if stubsOpening {
                openedURL = url
            } else {
                UIApplication.shared.open(url)
            }
        }
    }

    /// "simplyHermes 0.1.0-alpha.3 is available" above the chat list, with Update and Later. It is not there when
    /// there is nothing to offer, and a failed check never shows here.
    public struct AppUpdateBanner: View {
        @Bindable private var model: AppUpdateModel
        @Environment(\.scenePhase) private var scenePhase

        public init(model: AppUpdateModel = .shared) {
            self.model = model
        }

        public var body: some View {
            VStack(spacing: 0) {
                // Always there, so the check runs even while there is nothing to show.
                Color.clear.frame(height: 0)
                if let feed = model.available {
                    content(feed)
                }
            }
            .task { await model.checkIfDue() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.checkIfDue() } }
            }
        }

        private func content(_ feed: AppUpdateFeed) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("simplyHermes \(feed.version) is available")
                            .font(HermesFont.subheadline.weight(.semibold))
                            .foregroundStyle(HermesColor.primaryText)
                        if !feed.headline.isEmpty {
                            Text(feed.headline)
                                .font(HermesFont.footnote)
                                .foregroundStyle(HermesColor.secondaryText)
                                .lineLimit(3)
                        }
                    }
                } icon: {
                    Image(systemName: "arrow.down.app")
                        .foregroundStyle(HermesColor.accent)
                        .accessibilityHidden(true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { buttons }
                    VStack(alignment: .leading, spacing: 8) { buttons }
                }
                if let opened = model.openedURL {
                    Text(opened.absoluteString)
                        .font(HermesFont.caption)
                        .accessibilityIdentifier("appUpdate.opened")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("appUpdate.banner")
        }

        @ViewBuilder private var buttons: some View {
            Button("Later") { model.dismiss() }
                .buttonStyle(HermesButtonStyle(.tinted, fillsWidth: false))
                .accessibilityLabel("Remind me later")
                .accessibilityIdentifier("appUpdate.later")
            Button("Update") { model.openRelease() }
                .buttonStyle(HermesButtonStyle(.primary, fillsWidth: false))
                .accessibilityLabel("Open the release page to update")
                .accessibilityIdentifier("appUpdate.update")
        }
    }

    /// Settings > About: the installed version, Check for updates, and when the last check ran.
    public struct AppUpdateSettingsSection: View {
        @Bindable private var model: AppUpdateModel

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
                .accessibilityIdentifier("settings.checkForUpdates")
                if let feed = model.available {
                    Button("Open \(feed.version) release page") { model.openRelease() }
                        .accessibilityIdentifier("settings.openRelease")
                }
            } header: {
                Text("About")
            } footer: {
                Text(footer)
            }
        }

        private var footer: String {
            if model.available != nil {
                return "A newer build is out. Sign and install it the way you installed this one."
            }
            if let lastError = model.lastError { return "Couldn't check: \(lastError)" }
            if let lastCheck = model.lastCheck {
                return "Up to date. Last checked \(lastCheck.formatted(date: .abbreviated, time: .shortened))."
            }
            return "simplyHermes checks GitHub for a newer build once a day."
        }
    }
#endif
