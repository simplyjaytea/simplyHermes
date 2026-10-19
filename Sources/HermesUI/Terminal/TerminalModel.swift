#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// Where a terminal tab's socket stands while its pane is on screen.
    enum TerminalConnectionState: Equatable {
        case connecting
        case live
        case ended
        case failed(String)
    }

    /// The terminal tabs and what each one last reported. Owned by the shell, so the tabs survive leaving the Tools
    /// tab. A tab's socket is open only while its pane is on screen; the server keeps the PTY in the meantime.
    @MainActor
    @Observable
    final class TerminalModel {
        private(set) var tabs = TerminalTabs()
        private(set) var states: [UUID: TerminalConnectionState] = [:]
        /// Counts restarts per tab. A new count gives the pane a new identity, so it opens a new socket.
        private(set) var attempts: [UUID: Int] = [:]

        func open() {
            tabs.open()
        }

        func select(_ id: UUID) {
            tabs.select(id)
        }

        func close(_ id: UUID) {
            tabs.close(id)
            states[id] = nil
            attempts[id] = nil
        }

        func restart(_ id: UUID) {
            attempts[id, default: 0] += 1
            states[id] = nil
        }

        func attempt(of id: UUID) -> Int {
            attempts[id, default: 0]
        }

        func report(_ state: TerminalConnectionState, for id: UUID) {
            states[id] = state
        }
    }
#endif
