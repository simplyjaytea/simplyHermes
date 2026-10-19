import Foundation

/// What Settings > On-device models does with the download manager and the selection together. The rules live here,
/// not in the view model, so they can be tested without a screen.
public struct OnDeviceModelController: Sendable {
    public let manager: OnDeviceModelManager
    public let selection: OnDeviceModelSelection
    public let catalog: OnDeviceModelCatalog
    private let availableMemory: @Sendable () -> Int64?

    /// `availableMemory` is what this app may still allocate, from `os_proc_available_memory()`; nil when unknown.
    public init(
        manager: OnDeviceModelManager, selection: OnDeviceModelSelection, catalog: OnDeviceModelCatalog = .standard,
        availableMemory: @escaping @Sendable () -> Int64? = { nil }
    ) {
        self.manager = manager
        self.selection = selection
        self.catalog = catalog
        self.availableMemory = availableMemory
    }

    /// One row per catalog model, in catalog order. A model counts as selected only while it is the one that
    /// answers: after a memory warning the Apple model answers, and the row offers Use again.
    public func rows(states: [String: OnDeviceModelState]) -> [OnDeviceModelRow] {
        let route = selection.route
        let canRun = selection.canRunDownloadedModels
        let memory = availableMemory()
        return catalog.models.map { model in
            OnDeviceModelRow(
                model: model, state: states[model.id] ?? .notDownloaded, isSelected: route == .downloaded(model),
                canRun: canRun, availableMemoryBytes: memory)
        }
    }

    /// True when the Apple model is the one that answers now.
    public var appleModelIsInUse: Bool {
        selection.route == .apple
    }

    /// Does what a row button says. Delete unloads the model first, so its files are not in use when they go.
    public func perform(_ action: OnDeviceModelRow.Action, on model: OnDeviceModel) async throws {
        switch action {
        case .download, .resume, .retry:
            await manager.start(model.id)
        case .pause:
            await manager.pause(model.id)
        case .cancel:
            await manager.cancel(model.id)
        case .use:
            await selection.select(.downloaded(model.id))
        case .delete:
            await selection.modelWillBeDeleted(model.id)
            try await manager.delete(model.id)
        }
    }

    /// Makes the Apple model the one that answers.
    public func useAppleModel() async {
        await selection.select(.apple)
    }
}
