import HermesKit
import HermesUI
import SwiftUI

@main
struct HermesApp: App {
    @State private var model: ShellModel
    @State private var connections: ConnectionsModel
    private let launch: LaunchOptions
    private let integration: AppIntegration

    init() {
        let launch = LaunchOptions(defaults: .standard)
        self.launch = launch
        _connections = State(initialValue: Self.makeConnections(launch))
        let model = ShellModel()
        _model = State(initialValue: model)
        // Set up before any scene: a Live Activity or widget button can launch the app in the background.
        integration = AppIntegration(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model, connections: connections, launch: launch)
                .tint(HermesColor.accent)
                .onOpenURL { url in
                    if let id = HermesURL.chatID(from: url), model.session(id: id) != nil {
                        model.open(id)
                    }
                }
        }
        WindowGroup(id: ShellWindow.chat, for: String.self) { $sessionID in
            ChatWindow(model: model, sessionID: sessionID)
                .tint(HermesColor.accent)
        }
    }

    /// Saved servers. `-HermesOnboarding fresh` keeps them in memory with no Face ID, so UI tests start clean.
    @MainActor
    private static func makeConnections(_ launch: LaunchOptions) -> ConnectionsModel {
        if launch.onboarding == .fresh {
            let services = ConnectionServices(credentials: InMemoryCredentialStore(), unlocker: AlwaysUnlocked())
            return ConnectionsModel(store: nil, services: services)
        }
        return ConnectionsModel(
            store: ConnectionStore(fileURL: ConnectionStore.defaultFileURL()),
            services: ConnectionServices(credentials: KeychainCredentialStore()))
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
    }
}

struct RootView: View {
    let model: ShellModel
    let connections: ConnectionsModel
    let launch: LaunchOptions
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if connections.isEmpty && launch.onboarding != .skip {
                WelcomeView(connections: connections)
                    .transition(.opacity)
            } else {
                AdaptiveShell(
                    model: model, connections: connections, showsDebugLayoutMenu: launch.showsDebugLayoutSwitcher)
            }
        }
        .animation(HermesMotion.animation(HermesMotion.gentle, reduceMotion: reduceMotion), value: connections.isEmpty)
        .environment(\.hermesPosture, launch.posture ?? .flat)
        .task {
            if let layout = launch.layout {
                model.layoutOverride = layout
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
