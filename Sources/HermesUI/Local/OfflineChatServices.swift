#if canImport(UIKit)
    import Foundation
    import HermesKit

    /// What offline chat needs from the app (WP-65b): where offline chats are kept, which on-device model answers, and
    /// the Settings switch. The app installs it once at launch with ``install(cache:executor:)``. Until then offline
    /// chat stays off, so previews, snapshot tests and UI tests never open a cache file.
    @MainActor
    public final class OfflineChatServices {
        /// The installed services. Nil keeps offline chat off.
        public static var shared: OfflineChatServices?

        /// Where offline chats are kept.
        public let store: any OfflineChatStore
        /// The on-device model for the next reply. It is asked for every reply, so a model chosen in Settings applies
        /// at once.
        public let executor: @Sendable () -> any LocalModelExecutor
        /// The Settings switch for on-device features.
        public let settings: OnDeviceSettings
        /// Opens the screen where better on-device models are listed (WP-65c). Nil hides the "Get a better model" link.
        public var onGetBetterModel: (@MainActor () -> Void)?

        /// Creates the services.
        public init(
            store: any OfflineChatStore, executor: @escaping @Sendable () -> any LocalModelExecutor,
            settings: OnDeviceSettings = OnDeviceSettings(), onGetBetterModel: (@MainActor () -> Void)? = nil
        ) {
            self.store = store
            self.executor = executor
            self.settings = settings
            self.onGetBetterModel = onGetBetterModel
        }

        /// Installs the services over the app's cache, so offline chats live in the same file as the chat list.
        /// The default model is the Apple one, which reads the Settings switch. Pass `executor` to answer with
        /// another model (WP-65c); it replaces the Apple one.
        public static func install(cache: HermesCache, executor: (@Sendable () -> any LocalModelExecutor)? = nil) {
            shared = OfflineChatServices(store: cache.offlineChats, executor: executor ?? { appleOnDeviceModel() })
        }
    }

    #if canImport(FoundationModels)
        private func appleOnDeviceModel() -> any LocalModelExecutor {
            AppleLocalModel()
        }
    #else
        /// Stands in where the Apple model does not exist, so offline chat reports "unsupported".
        private struct MissingOnDeviceModel: LocalModelExecutor {
            var availability: LocalModelAvailability { .unavailable(.unsupported) }

            func respond(instructions: String, prompt: String) async throws -> String {
                throw CancellationError()
            }
        }

        private func appleOnDeviceModel() -> any LocalModelExecutor {
            MissingOnDeviceModel()
        }
    #endif
#endif
