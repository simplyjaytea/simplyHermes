import Foundation
import HermesKit

/// Where the app and the widget extension keep the small files they hand to each other.
enum IntegrationStorage {
    /// The App Group container, looked up once per process. The group id is read at runtime because SideStore renames
    /// it (see ``SharedContainer``).
    static let resolution = SharedContainer.resolve(
        infoDictionary: Bundle.main.infoDictionary,
        containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    )

    /// The shared folder, or nil when this install has no App Group.
    static var sharedDirectory: URL? { resolution.directory }
}
