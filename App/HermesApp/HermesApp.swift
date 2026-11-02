import HermesKit
import HermesUI
import SwiftUI

@main
struct HermesApp: App {
    @State private var model: ShellModel
    @State private var connections: ConnectionsModel
    @State private var sessionsList: SessionsListModel
    private let launch: LaunchOptions
    private let integration: AppIntegration
    private let entry: EntryIntegration
    @AppStorage(OnDeviceSettings.key) private var onDeviceEnabled = true
    @AppStorage(AppearanceSettings.key) private var storedPresetRaw: String = AppearancePreset.system.rawValue

    private var activePreset: AppearancePreset {
        AppearancePreset.fallback(for: storedPresetRaw)
    }

    static func applyLaunchReset(_ launch: LaunchOptions, defaults: UserDefaults = .standard) {
        AppearanceSettings.applyLaunchReset(resetAppearance: launch.resetAppearance, defaults: defaults)
    }

    init() {
        let launch = LaunchOptions(defaults: .standard)
        AppearanceSettings.applyLaunchReset(resetAppearance: launch.resetAppearance, defaults: .standard)
        self.launch = launch
        let connections = Self.makeConnections(launch)
        _connections = State(initialValue: connections)
        _sessionsList = State(initialValue: Self.makeSessionsList(connections, launch))
        // UI tests keep drafts in memory, so a draft typed in one run is not in the field at the start of the next.
        let model = ShellModel(
            sessions: Self.placeholderSessions(launch),
            draftDefaults: launch.onboarding == nil ? UserDefaults.standard : nil)
        _model = State(initialValue: model)
        // Set up before any scene: a Live Activity or widget button can launch the app in the background.
        let integration = AppIntegration(model: model)
        self.integration = integration
        // Intents, Quick Entry, shared items and Spotlight results all arrive through this one object.
        entry = EntryIntegration(model: model, connections: connections, integration: integration)
        // UI tests set -HermesOnboarding; a tip popover would cover the controls they tap.
        HermesTips.configure(enabled: launch.onboarding == nil)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, connections: connections, sessionsList: sessionsList, launch: launch)
                .integrationHost(entry)
                .hermesAppearance(activePreset)
                .environment(\.onDeviceModels, OnDeviceModelServices.shared.model)
                .onDeviceModelsSheet(OnDeviceModelServices.shared.model, isEnabled: $onDeviceEnabled)
                .onOpenURL { url in
                    if let id = HermesURL.chatID(from: url), model.session(id: id) != nil {
                        model.open(id)
                    } else if let reference = HermesURL.sessionReference(from: url) {
                        model.pendingSessionReference = reference
                    }
                }
        }
        WindowGroup(id: ShellWindow.chat, for: String.self) { $sessionID in
            ChatWindow(model: model, sessionID: sessionID)
                .hermesAppearance(activePreset)
                .environment(\.onDeviceModels, OnDeviceModelServices.shared.model)
        }
    }

    /// Placeholder chats are fake, so only debug builds have them, and only when a UI test asks. A release build starts
    /// with no chats.
    private static func placeholderSessions(_ launch: LaunchOptions) -> [ChatSessionSummary] {
        #if DEBUG
            if launch.showsSampleChats { return ShellModel.sampleSessions }
        #endif
        return []
    }

    /// The chat list cache. UI tests keep it in memory so runs never share saved chats.
    @MainActor
    private static func makeSessionsList(_ saved: ConnectionsModel, _ launch: LaunchOptions) -> SessionsListModel {
        // UI tests use an in-memory cache unless they ask for a persistent one (DEBUG seam, UITestSeams).
        let url = UITestSeams.persistentCacheURL ?? (launch.onboarding == nil ? Self.cacheFileURL() : nil)
        let file = url.flatMap { try? HermesCache(url: $0) }
        let cache = file ?? (try? HermesCache())
        guard let cache else { preconditionFailure("The in-memory cache cannot fail to open") }
        // WP-3: messages waiting to reach the server are kept in the same file, so they survive a relaunch. When the
        // file would not open, the outbox is in memory and sending is refused, rather than losing messages silently.
        // UI tests keep the cache in memory on purpose, so they count as durable. A test's on-disk cache is durable too.
        OutboxServices.install(cache.outbox, durable: file != nil || launch.onboarding != nil)
        // WP-7: local chats are kept in the same cache file as the chat list. They exist nowhere else, so they stay off
        // when the file would not open and the cache fell back to memory. UI tests keep it in memory on purpose.
        if file != nil || launch.onboarding != nil {
            LocalChatServices.install(
                cache: cache, answerer: localAnswerer(),
                answeringModel: { OnDeviceModelServices.shared.selection.answeringModel })
        }
        UITestSeams.install()
        return SessionsListModel(connections: saved, cache: cache)
    }

    /// The model local chats answer with. A UI test can name a fixed fake; release builds never can.
    @MainActor
    private static func localAnswerer() -> @Sendable () -> any LocalChatAnswerer {
        #if DEBUG
            if let name = UITestSeams.localExecutorName { return UITestSeams.answerer(named: name) }
        #endif
        return OnDeviceModelServices.shared.answerer
    }

    private static func cacheFileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("simplyHermes", isDirectory: true).appendingPathComponent("cache.sqlite")
    }

    /// Saved servers. `-HermesOnboarding fresh` keeps them in memory with no Face ID, so UI tests start clean.
    @MainActor
    private static func makeConnections(_ launch: LaunchOptions) -> ConnectionsModel {
        if launch.onboarding == .fresh {
            let services = ConnectionServices(credentials: InMemoryCredentialStore(), unlocker: AlwaysUnlocked())
            return ConnectionsModel(store: nil, services: services)
        }
        let connections = ConnectionsModel(
            store: ConnectionStore(fileURL: ConnectionStore.defaultFileURL()),
            services: ConnectionServices(credentials: KeychainCredentialStore()))
        connections.applyOpenOnLaunch()
        return connections
    }
}

/// Launch arguments for UI tests and debugging, read from `UserDefaults`
/// (pass them as `-HermesLayout innerLandscape`).
struct LaunchOptions {
    /// Forces a layout: compact, innerPortrait, innerLandscape, halfFold or tent.
    var layout: DisplayLayout?
    /// Forces a posture until WP-02 reads the real one: flat, halfFolded or tent.
    var posture: DevicePosture?
    /// Shows the layout switcher used by the fold UI test.
    var showsDebugLayoutSwitcher: Bool
    /// "stream" starts a demo reply that lasts about three minutes, so the fold UI test can change layout mid-stream
    /// even on a slow CI run. "liveActivity" starts one long enough for CI to screenshot the Dynamic Island.
    var demo: String?
    /// "skip" opens the shell even with no saved server; "fresh" starts with no servers, in memory.
    var onboarding: Onboarding?
    /// Opens this section first, so a UI test can start on it without tapping the tab bar.
    var section: AppSection?
    /// Resets appearance settings to system defaults on launch (pass as `-HermesResetAppearance YES`).
    var resetAppearance: Bool
    /// Debug builds only: starts with the sample chats. UI tests that need them pass `-HermesSampleChats YES`.
    var showsSampleChats: Bool

    enum Onboarding: String {
        case skip
        case fresh
    }

    init(defaults: UserDefaults) {
        layout = defaults.string(forKey: "HermesLayout").flatMap(DisplayLayout.init(rawValue:))
        posture = defaults.string(forKey: "HermesPosture").flatMap(DevicePosture.init(rawValue:))
        showsDebugLayoutSwitcher = defaults.bool(forKey: "HermesDebugLayoutSwitcher")
        demo = defaults.string(forKey: "HermesDemo")
        onboarding = defaults.string(forKey: "HermesOnboarding").flatMap(Onboarding.init(rawValue:))
        section = defaults.string(forKey: "HermesSection").flatMap(AppSection.init(rawValue:))
        resetAppearance = defaults.bool(forKey: "HermesResetAppearance")
        showsSampleChats = defaults.bool(forKey: "HermesSampleChats")
    }
}

struct RootView: View {
    let model: ShellModel
    let connections: ConnectionsModel
    let sessionsList: SessionsListModel
    let launch: LaunchOptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if connections.isEmpty && launch.onboarding != .skip {
                WelcomeView(connections: connections)
                    .transition(.opacity)
            } else {
                AdaptiveShell(
                    model: model, connections: connections, sessionsList: sessionsList,
                    showsDebugLayoutMenu: launch.showsDebugLayoutSwitcher)
            }
        }
        .animation(HermesMotion.animation(HermesMotion.gentle, reduceMotion: reduceMotion), value: connections.isEmpty)
        .environment(\.hermesPosture, launch.posture ?? .flat)
        .overlay(alignment: .topLeading) { UITestSeams.readout() }
        .task {
            if let layout = launch.layout {
                model.layoutOverride = layout
            }
            if let section = launch.section {
                model.selectedSection = section
            }
            #if DEBUG
                if launch.demo == "stream", let id = model.selectedSessionID {
                    model.startDemoStream(in: id, words: 1500)
                }
                if launch.demo == "liveActivity", let id = model.selectedSessionID {
                    model.startDemoStream(in: id, words: 1500)
                }
            #endif
        }
    }
}
