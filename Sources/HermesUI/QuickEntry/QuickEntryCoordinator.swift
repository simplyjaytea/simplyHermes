#if canImport(UIKit)
    import HermesKit
    import Observation

    /// What the Quick Entry sheet shows and keeps. The app presents the sheet while `isPresented` is true.
    ///
    /// The Action button, the Control Center control, Siri and the `simplyhermes://quick-entry` link all end here:
    /// they call ``present(prefill:)`` and nothing else.
    @MainActor
    @Observable
    public final class QuickEntryCoordinator {
        public var isPresented = false
        /// The text in the box. It stays when the sheet is dismissed without sending, so reopening it picks up where
        /// the user left off.
        public var text = ""
        /// True when the user chose a new chat instead of the default destination.
        public var startsNewChat = false
        /// The chat the user used last. ``QuickEntryPolicy`` decides whether Quick Entry follows up in it.
        public var lastChat: RecentChat?

        public init() {}

        /// Opens the sheet. `prefill` replaces the text; without it, what was typed before stays.
        public func present(prefill: String? = nil) {
            if let prefill, !prefill.isEmpty { text = prefill }
            isPresented = true
        }

        /// Closes the sheet and clears it, once a message has gone out.
        public func finish() {
            isPresented = false
            text = ""
            startsNewChat = false
        }
    }
#endif
