#if canImport(UIKit)
    import Observation
    import UIKit

    /// Whether the software keyboard is on screen. A view that must give up room while the user types reads
    /// ``isUp``. The watcher starts with the shell, so a view made while the keyboard is already up sees it.
    @MainActor
    @Observable
    final class KeyboardWatcher {
        static let shared = KeyboardWatcher()

        private(set) var isUp = false

        private init() {
            let center = NotificationCenter.default
            center.addObserver(
                forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.isUp = true }
            }
            center.addObserver(
                forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.isUp = false }
            }
        }

        /// Starts the watcher. Safe to call more than once.
        static func start() {
            _ = shared
        }
    }
#endif
