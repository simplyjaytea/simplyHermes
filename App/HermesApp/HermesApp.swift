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

    init() {
        let launch = LaunchOptions(defaults: .standard)
        self.launch = launch
        let connections = Self.makeConnections(launch)
        _connections = State(initialValue: connections)
        _sessionsList = State(initialValue: Self.makeSessionsList(connections, launch))
        let model = ShellModel()
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
                .tint(HermesColor.accent)
                .environment(\.onDeviceModels, OnDeviceModelServices.shared.model)
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
                .tint(HermesColor.accent)
                .environment(\.onDeviceModels, OnDeviceModelServices.shared.model)
        }
    }

    /// The chat list cache. UI tests keep it in memory so runs never share saved chats.
    @MainActor
    private static func makeSessionsList(_ saved: ConnectionsModel, _ launch: LaunchOptions) -> SessionsListModel {
        let url = launch.onboarding == nil ? Self.cacheFileURL() : nil
        let file = url.flatMap { try? HermesCache(url: $0) }
        let cache = file ?? (try? HermesCache())
        guard let cache else { preconditionFailure("The in-memory cache cannot fail to open") }
        // WP-65b: offline chats are kept in the same cache file as the chat list. They exist nowhere else, so they stay
        // off when the file would not open and the cache fell back to memory. UI tests keep it in memory on purpose.
        if file != nil || launch.onboarding != nil { OfflineChatServices.install(cache: cache) }
        return SessionsListModel(connections: saved, cache: cache)
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
    /// "stream" starts a long demo reply in the first chat; "liveActivity" starts one long enough
    /// for CI to screenshot the Dynamic Island from another app.
    var demo: String?
    /// "skip" opens the shell even with no saved server; "fresh" starts with no servers, in memory.
    var onboarding: Onboarding?
    /// Opens this section first, so a UI test can start on it without tapping the tab bar.
    var section: AppSection?

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
        .task {
            if let layout = launch.layout {
                model.layoutOverride = layout
            }
            if let section = launch.section {
                model.selectedSection = section
            }
            if launch.demo == "stream", let id = model.selectedSessionID {
                model.startDemoStream(in: id, words: 400)
            }
            if launch.demo == "liveActivity", let id = model.selectedSessionID {
                model.startDemoStream(in: id, words: 1500)
            }
        }
    }
}
