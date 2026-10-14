#if canImport(UIKit)
    import SwiftUI

    /// Haptic moments. Plan Q8 chose rich haptics. They play through SwiftUI's
    /// `sensoryFeedback`, so the system's own haptics setting still turns them off.
    public enum HermesFeedback: Sendable, CaseIterable {
        case send
        case streamStarted
        case approvalNeeded
        case approved
        case denied
        case turnComplete
        case error
        case selection

        public var sensoryFeedback: SensoryFeedback {
            switch self {
            case .send: .impact(flexibility: .soft, intensity: 0.7)
            case .streamStarted: .impact(flexibility: .soft, intensity: 0.4)
            case .approvalNeeded: .warning
            case .approved: .success
            case .denied: .impact(weight: .medium)
            case .turnComplete: .success
            case .error: .error
            case .selection: .selection
            }
        }
    }

    extension View {
        /// Plays `feedback` each time `trigger` changes.
        public func hermesFeedback<Trigger: Equatable>(_ feedback: HermesFeedback, trigger: Trigger) -> some View {
            sensoryFeedback(feedback.sensoryFeedback, trigger: trigger)
        }
    }
#endif
