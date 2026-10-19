import Foundation
import HermesKit

/// The shared container, found the same way the app and the widgets find it. The extension keeps nothing else: it
/// writes a share into the outbox and the app sends it. The extension never opens a connection.
enum ShareStorage {
    static let resolution = SharedContainer.resolve(
        infoDictionary: Bundle.main.infoDictionary,
        containerURL: { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
    )

    /// The shared folder, or nil when this install has no App Group.
    static var directory: URL? { resolution.directory }
}
