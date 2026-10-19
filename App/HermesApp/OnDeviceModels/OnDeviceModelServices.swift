import Foundation
import HermesKit
import HermesUI
import UIKit
import os

/// Builds the on-device model pieces (plan WP-65c) once and keeps them for the life of the app: the download manager,
/// the choice of model, the MLX runtime and the model behind Settings > On-device models.
///
/// It also answers iOS. A memory warning unloads the MLX model and lets the Apple model answer. Coming back to the
/// foreground continues the downloads that a lost connection stopped.
@MainActor
final class OnDeviceModelServices {
    static let shared = OnDeviceModelServices()

    let manager: OnDeviceModelManager
    let selection: OnDeviceModelSelection
    /// The model behind the Settings screen. The app puts it in the environment as `onDeviceModels`.
    let model: OnDeviceModelsModel

    /// The model that answers on-device chats and helpers. It follows the choice made in Settings, so hand this to
    /// `OfflineChatServices.install(cache:executor:)` (WP-65b) instead of the Apple model.
    nonisolated let executor: @Sendable () -> any LocalModelExecutor

    private var observers: [any NSObjectProtocol] = []

    /// `isEnabled` is the Settings switch for on-device features (plan WP-65b). It reads the switch in `UserDefaults`.
    init(
        apple: any LocalModelExecutor = AppleLocalModel(),
        isEnabled: @escaping @Sendable () -> Bool = { OnDeviceSettings().isEnabled }
    ) {
        let storage = OnDeviceModelStorage(root: OnDeviceModelStorage.defaultRoot())
        let manager = OnDeviceModelManager(storage: storage, downloader: URLSessionModelFileDownloader())
        let gate = OnDeviceMemoryGate { availableAppMemory() }
        let selection = OnDeviceModelSelection(
            apple: apple, storage: storage, runtime: makeMLXRuntime(memoryGate: gate), isEnabled: isEnabled)
        self.manager = manager
        self.selection = selection
        executor = { selection }
        model = OnDeviceModelsModel(
            controller: OnDeviceModelController(
                manager: manager, selection: selection, availableMemory: gate.availableBytes),
            storage: storage)
        observe()
        Task { await manager.reload() }
    }

    /// Opens the model list as a sheet. Offline chat calls it from "Get a better model" (plan Q45).
    func presentModelList() {
        model.presentList()
    }

    private func observe() {
        let center = NotificationCenter.default
        let onMemoryWarning: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.handleMemoryWarning() }
        }
        let onBecameActive: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in await self?.manager.resumeInterrupted() }
        }
        observers.append(
            center.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main,
                using: onMemoryWarning))
        observers.append(
            center.addObserver(
                forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: onBecameActive))
    }

    private func handleMemoryWarning() async {
        await selection.handleMemoryWarning()
        model.refresh()
    }
}

/// Bytes this app may still allocate, or nil when iOS does not say (it answers 0 outside a device).
private func availableAppMemory() -> Int64? {
    let bytes = os_proc_available_memory()
    return bytes > 0 ? Int64(bytes) : nil
}
