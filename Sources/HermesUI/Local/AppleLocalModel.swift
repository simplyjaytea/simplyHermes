#if canImport(FoundationModels)
    import FoundationModels
    import HermesKit

    /// The Apple on-device model behind ``LocalHelpers``. A new session per call keeps jobs from sharing context.
    public struct AppleLocalModel: LocalModelExecutor {
        private let isEnabled: @Sendable () -> Bool

        /// `isEnabled` reads the Settings switch for on-device features (plan WP-65b). By default it is
        /// ``OnDeviceSettings``, so turning the switch off in Settings stops the model at once.
        public init(isEnabled: @escaping @Sendable () -> Bool = { OnDeviceSettings().isEnabled }) {
            self.isEnabled = isEnabled
        }

        public var availability: LocalModelAvailability {
            guard isEnabled() else { return .unavailable(.switchedOff) }
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(.deviceNotEligible):
                return .unavailable(.unsupported)
            case .unavailable(.appleIntelligenceNotEnabled):
                return .unavailable(.disabled)
            case .unavailable:
                return .unavailable(.notReady)
            }
        }

        public func respond(instructions: String, prompt: String) async throws -> String {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt).content
        }
    }
#endif
