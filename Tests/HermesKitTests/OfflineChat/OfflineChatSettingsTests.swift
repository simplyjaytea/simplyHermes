import Foundation
import Testing

@testable import HermesKit

struct OfflineChatSettingsTests {
    /// A private `UserDefaults` suite, removed again when the test is done.
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let name = "OfflineChatSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(defaults)
    }

    @Test func onDeviceFeaturesAreOnByDefault() throws {
        try withDefaults { defaults in
            #expect(OnDeviceSettings(defaults: defaults).isEnabled)
        }
    }

    @Test func theSwitchIsRememberedAndSharedByEveryReader() throws {
        try withDefaults { defaults in
            let settings = OnDeviceSettings(defaults: defaults)
            settings.isEnabled = false
            #expect(!settings.isEnabled)
            // A second reader of the same defaults (the executor's closure) sees the change at once.
            #expect(!OnDeviceSettings(defaults: defaults).isEnabled)
            #expect(defaults.object(forKey: OnDeviceSettings.key) as? Bool == false)
            settings.isEnabled = true
            #expect(OnDeviceSettings(defaults: defaults).isEnabled)
        }
    }

    @Test func theSettingsScreenAndTheSettingUseTheSameKey() throws {
        // `@AppStorage(OnDeviceSettings.key)` in the Settings screen writes this key directly.
        try withDefaults { defaults in
            defaults.set(false, forKey: OnDeviceSettings.key)
            #expect(!OnDeviceSettings(defaults: defaults).isEnabled)
            defaults.removeObject(forKey: OnDeviceSettings.key)
            #expect(OnDeviceSettings(defaults: defaults).isEnabled)
        }
    }

    @Test func turningTheSwitchOffMakesTheRouteUnavailableInAnOutage() throws {
        try withDefaults { defaults in
            let settings = OnDeviceSettings(defaults: defaults)
            var router = OfflineRouter()
            router.observe(.unreachable, at: 0)
            #expect(router.route(onDeviceEnabled: settings.isEnabled, availability: .available, at: 5) == .offline)
            settings.isEnabled = false
            let route = router.route(onDeviceEnabled: settings.isEnabled, availability: .available, at: 5)
            #expect(route == .unavailable(.switchedOff))
        }
    }

    @Test func aSwitchedOffExecutorAnswersNothingToTheHelpers() async throws {
        // The shape the Apple executor uses: its availability reads the switch.
        struct SwitchedExecutor: LocalModelExecutor {
            let settings: OnDeviceSettings
            var availability: LocalModelAvailability {
                settings.isEnabled ? .available : .unavailable(.switchedOff)
            }
            func respond(instructions: String, prompt: String) async throws -> String { "answer" }
        }
        let name = "OfflineChatSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = OnDeviceSettings(defaults: defaults)
        let helpers = LocalHelpers(executor: SwitchedExecutor(settings: settings))
        #expect(await helpers.polish("hello") == "answer")
        settings.isEnabled = false
        #expect(await helpers.polish("hello") == nil)
        #expect(!helpers.isAvailable)
    }
}
