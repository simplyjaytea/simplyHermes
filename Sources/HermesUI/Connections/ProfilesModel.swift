#if canImport(UIKit)
    import Foundation
    import HermesKit
    import Observation

    /// The profiles (bots) of the active server and the one the user is working as (WP-41).
    ///
    /// The choice is remembered per saved connection and sent to the connection manager, which scopes every REST and
    /// gateway call with it. A remembered profile the server no longer has is dropped on the next refresh.
    @MainActor
    @Observable
    public final class ProfilesModel {
        public private(set) var selection = ProfileSelection()
        @ObservationIgnored private let connections: ConnectionsModel
        @ObservationIgnored private let defaults: UserDefaults

        public init(connections: ConnectionsModel, defaults: UserDefaults = .standard) {
            self.connections = connections
            self.defaults = defaults
        }

        /// Reads the profile list of the active server and applies the remembered choice. Does nothing until the
        /// connection is up.
        public func refresh() async {
            guard let connection = connections.active, let manager = connections.manager,
                let rest = await manager.rest(for: connection.id)
            else { return }
            let stored = defaults.string(forKey: Self.key(connection.id))
            await manager.setProfile(stored, for: connection.id)
            guard let profiles = try? await rest.profiles() else { return }
            let resolved = ProfileSelection.resolve(profiles: profiles, stored: stored)
            if resolved.chosen != stored { defaults.removeObject(forKey: Self.key(connection.id)) }
            await manager.setProfile(resolved.chosen, for: connection.id)
            selection = resolved
        }

        /// Works as `name` from now on, on the active server.
        public func select(_ name: String) {
            guard let connection = connections.active, selection.profiles.contains(where: { $0.name == name })
            else { return }
            defaults.set(name, forKey: Self.key(connection.id))
            selection.chosen = name
            if let manager = connections.manager {
                Task { await manager.setProfile(name, for: connection.id) }
            }
        }

        private static func key(_ id: UUID) -> String { "profile.\(id.uuidString)" }

        /// A model with fixed profiles, for previews and snapshots.
        public static func preview(_ selection: ProfileSelection) -> ProfilesModel {
            let model = ProfilesModel(
                connections: .preview(), defaults: UserDefaults(suiteName: "preview.profiles") ?? .standard)
            model.selection = selection
            return model
        }
    }
#endif
