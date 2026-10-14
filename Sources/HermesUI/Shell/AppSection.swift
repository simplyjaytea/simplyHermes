#if canImport(UIKit)
    import SwiftUI

    /// Top-level sections: tabs on the outer screen, sidebar rows on the inner screen (plan Q6).
    public enum AppSection: String, CaseIterable, Identifiable, Hashable, Sendable {
        case chats
        case bots
        case automations
        case tools
        case settings

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .chats: "Chats"
            case .bots: "Bots"
            case .automations: "Automations"
            case .tools: "Tools"
            case .settings: "Settings"
            }
        }

        public var systemImage: String {
            switch self {
            case .chats: "bubble.left.and.bubble.right"
            case .bots: "person.2"
            case .automations: "clock.arrow.circlepath"
            case .tools: "terminal"
            case .settings: "gearshape"
            }
        }

        /// The work package that fills this section in.
        var plannedIn: String {
            switch self {
            case .chats: "WP-30 and WP-40"
            case .bots: "WP-42"
            case .automations: "WP-50"
            case .tools: "WP-52, WP-54, WP-55, WP-61 and WP-62"
            case .settings: "WP-53"
            }
        }
    }
#endif
