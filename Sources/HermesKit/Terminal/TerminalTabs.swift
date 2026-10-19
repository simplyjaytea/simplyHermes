import Foundation

/// One terminal tab. Its attach token names the PTY on the server, so the tab reattaches to the same TUI session
/// after it was hidden.
public struct TerminalTab: Identifiable, Sendable, Equatable {
    /// Identifies the tab in the app.
    public let id: UUID
    /// Sent as `attach=`. A new token starts a new TUI session.
    public let attachToken: String
    /// Shown in the tab rail, such as "Terminal 2".
    public let title: String
}

/// The terminal tabs of one server and the selected one. The server keeps each PTY alive for a while, but the tab
/// list lives on this device.
public struct TerminalTabs: Sendable, Equatable {
    /// Open tabs, in the order they were opened.
    public private(set) var tabs: [TerminalTab] = []
    /// The selected tab's id, or nil when no tab is open.
    public private(set) var selectedID: UUID?
    private var opened = 0

    /// Creates an empty tab list.
    public init() {}

    /// The selected tab.
    public var selected: TerminalTab? {
        tabs.first { $0.id == selectedID }
    }

    /// Opens a tab with a new attach token and selects it.
    @discardableResult
    public mutating func open() -> TerminalTab {
        opened += 1
        let tab = TerminalTab(
            id: UUID(), attachToken: UUID().uuidString.lowercased(), title: "Terminal \(opened)")
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    /// Selects a tab. An unknown id changes nothing.
    public mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Removes a tab. Closing the selected tab selects the one before it, or the first tab when it was first.
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        guard selectedID == id else { return }
        selectedID = tabs.isEmpty ? nil : tabs[max(0, index - 1)].id
    }
}
