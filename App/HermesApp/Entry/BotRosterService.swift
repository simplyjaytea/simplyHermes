import Foundation
import HermesKit
import HermesUI
import Observation

/// Keeps the bots (profiles) of the active server on the phone, and switches to one on request.
///
/// Siri, Shortcuts and Spotlight need the bot names while the app may not be connected yet, so the roster is saved
/// whenever the profile list is read. It reads the list the same way the profile chip in the header does.
@MainActor
final class BotRosterService {
    enum Selection {
        case selected
        /// The server is connected and has no such bot.
        case unknown
        /// No server answered in time.
        case notConnected
    }

    private(set) var roster: BotRoster
    private let connections: ConnectionsModel
    private let profiles: ProfilesModel
    private let store: JSONFileStore<BotRoster>
    private let onChange: @MainActor (BotRoster) -> Void

    /// - Parameter onChange: called with the saved roster at start and again whenever the bots change.
    init(connections: ConnectionsModel, directory: URL, onChange: @escaping @MainActor (BotRoster) -> Void) {
        self.connections = connections
        profiles = ProfilesModel(connections: connections)
        store = BotRoster.store(directory: directory)
        roster = store.load() ?? BotRoster(bots: [], updatedAt: .distantPast)
        self.onChange = onChange
    }

    func start() {
        onChange(roster)
        watch()
    }

    /// Reads the profile list again each time the active server comes up.
    private func watch() {
        let isUp = withObservationTracking {
            guard let id = connections.active?.id, case .connected = connections.phase(of: id) else { return false }
            return true
        } onChange: { [weak self] in
            Task { @MainActor in self?.watch() }
        }
        if isUp {
            Task { await self.refresh() }
        }
    }

    private func refresh() async {
        await profiles.refresh()
        let found = profiles.selection.profiles
        guard !found.isEmpty else { return }
        let next = BotRoster(profiles: found, updatedAt: Date())
        guard !next.hasSameContent(as: roster) else { return }
        roster = next
        try? store.save(next)
        onChange(next)
    }

    /// Works as `bot` from now on. Waits a little for the server, because a request from Siri can arrive while the app
    /// is still connecting.
    func select(_ bot: BotRoster.Bot) async -> Selection {
        for attempt in 0..<24 {
            guard connections.active != nil else { return .notConnected }
            let loaded = profiles.selection.profiles
            if loaded.contains(where: { $0.name == bot.name }) {
                profiles.select(bot.name)
                return .selected
            }
            if !loaded.isEmpty { return .unknown }
            if attempt % 4 == 0 { await profiles.refresh() }
            try? await Task.sleep(for: .milliseconds(500))
        }
        return .notConnected
    }
}
