import Foundation

/// What the user picked in Settings > On-device models.
public enum OnDeviceModelChoice: Sendable, Hashable, Codable {
    /// The Apple on-device model. The default.
    case apple
    /// A downloaded model, by catalog id.
    case downloaded(String)
}

/// Why a downloaded model cannot answer.
public enum OnDeviceModelError: Error, Sendable, Equatable {
    /// The phone does not have enough free memory to load the model.
    case notEnoughMemory(needed: Int64, available: Int64)
}

/// The part of the model runtime the selection needs. The app implements it with MLX; HermesKit never imports MLX, so
/// the package keeps building and testing on Linux.
public protocol OnDeviceModelRuntime: Sendable {
    /// An executor for a downloaded model whose files are in `folder`, or nil when this device cannot run it
    /// (the Simulator, a device with no Metal GPU).
    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)?
    /// Frees the memory of every loaded model. Models load again on their next use.
    func unloadAll() async
}

/// Checks that the phone has the memory a model needs before the runtime loads it. The app supplies the number from
/// `os_proc_available_memory()`.
public struct OnDeviceMemoryGate: Sendable {
    /// Bytes this app can still allocate, or nil when unknown (then loading is allowed).
    public var availableBytes: @Sendable () -> Int64?

    public init(availableBytes: @escaping @Sendable () -> Int64?) {
        self.availableBytes = availableBytes
    }

    /// Throws ``OnDeviceModelError/notEnoughMemory(needed:available:)`` when the estimate does not fit.
    public func check(_ model: OnDeviceModel) throws {
        guard let available = availableBytes(), available < model.estimatedMemoryBytes else { return }
        throw OnDeviceModelError.notEnoughMemory(needed: model.estimatedMemoryBytes, available: available)
    }
}

/// Decides which on-device model answers: the Apple model by default, or a downloaded model once the user picked one.
///
/// This type is itself a ``LocalModelExecutor``, so the offline chat and the helpers can hold it and always reach the
/// current choice: it looks at the choice on every call. It falls back to the Apple model, and never fails because of
/// the choice, when
/// - the picked model is not on the phone (deleted, not finished, or no longer in the catalog),
/// - the runtime cannot run it on this device,
/// - iOS sent a memory warning (plan WP-65c). The runtime unloads, and the Apple model stays in charge until the user
///   picks a downloaded model again,
/// - or loading the model fails for lack of memory.
///
/// The Settings switch for on-device features (plan WP-65b) is `isEnabled`: when it is off, nothing answers.
public final class OnDeviceModelSelection: LocalModelExecutor, @unchecked Sendable {
    /// Which model would answer right now.
    public enum Route: Sendable, Equatable {
        case apple
        case downloaded(OnDeviceModel)
    }

    /// The Apple model, for callers that want it whatever the user picked (titles, for example).
    public let apple: any LocalModelExecutor

    private let storage: OnDeviceModelStorage
    private let catalog: OnDeviceModelCatalog
    private let runtime: (any OnDeviceModelRuntime)?
    private let isEnabled: @Sendable () -> Bool
    private let lock = NSLock()
    private var savedChoice: OnDeviceModelChoice
    private var suspendedByMemory = false
    private var downloadedExecutors: [String: any LocalModelExecutor] = [:]

    /// `runtime` is nil where nothing can run a downloaded model: then the Apple model always answers.
    public init(
        apple: any LocalModelExecutor,
        storage: OnDeviceModelStorage,
        catalog: OnDeviceModelCatalog = .standard,
        runtime: (any OnDeviceModelRuntime)? = nil,
        isEnabled: @escaping @Sendable () -> Bool = { true }
    ) {
        self.apple = apple
        self.storage = storage
        self.catalog = catalog
        self.runtime = runtime
        self.isEnabled = isEnabled
        savedChoice = storage.loadChoice() ?? .apple
    }

    // MARK: Reading

    /// What the user picked. It can differ from ``route``.
    public var choice: OnDeviceModelChoice {
        lock.withLock { savedChoice }
    }

    /// Which model answers right now, after the fallbacks.
    public var route: Route {
        resolve().route
    }

    /// True when a downloaded model could run on this device: the app supplied a runtime.
    public var canRunDownloadedModels: Bool {
        runtime != nil
    }

    /// True after a memory warning moved the answers back to the Apple model.
    public var isSuspendedByMemoryWarning: Bool {
        lock.withLock { suspendedByMemory }
    }

    // MARK: Changing

    /// Saves the choice. Picking a model again after a memory warning lets it load again. A different choice unloads
    /// the old model first: two models in memory at once would be the surest way to a memory warning.
    public func select(_ choice: OnDeviceModelChoice) async {
        if setChoice(choice) { await runtime?.unloadAll() }
    }

    /// iOS sent a memory warning: unload the downloaded model and let the Apple model answer.
    public func handleMemoryWarning() async {
        lock.withLock {
            if case .downloaded = savedChoice { suspendedByMemory = true }
        }
        await runtime?.unloadAll()
    }

    /// Call before a model's files are deleted. Unloads it, forgets its executor, and falls back to the Apple model
    /// when it was the one in use.
    public func modelWillBeDeleted(_ id: String) async {
        let wasInUse = lock.withLock { () -> Bool in
            downloadedExecutors[id] = nil
            return savedChoice == .downloaded(id)
        }
        if wasInUse { setChoice(.apple) }
        await runtime?.unloadAll()
    }

    // MARK: LocalModelExecutor

    public var availability: LocalModelAvailability {
        guard isEnabled() else { return .unavailable(.switchedOff) }
        return resolve().executor.availability
    }

    public func respond(instructions: String, prompt: String) async throws -> String {
        let (route, executor) = resolve()
        do {
            return try await executor.respond(instructions: instructions, prompt: prompt)
        } catch OnDeviceModelError.notEnoughMemory where route != .apple {
            await handleMemoryWarning()
            return try await apple.respond(instructions: instructions, prompt: prompt)
        }
    }

    // MARK: Resolution

    /// Stores the choice and clears a memory-warning suspension. Returns true when the choice changed.
    @discardableResult
    private func setChoice(_ choice: OnDeviceModelChoice) -> Bool {
        let changed = lock.withLock { () -> Bool in
            let previous = savedChoice
            savedChoice = choice
            suspendedByMemory = false
            return previous != choice
        }
        storage.saveChoice(choice)
        return changed
    }

    private func resolve() -> (route: Route, executor: any LocalModelExecutor) {
        let (choice, suspended) = lock.withLock { (savedChoice, suspendedByMemory) }
        guard !suspended, let runtime, case .downloaded(let id) = choice, let model = catalog.model(id: id),
            storage.isDownloaded(model)
        else { return (.apple, apple) }
        if let cached = lock.withLock({ downloadedExecutors[id] }) { return (.downloaded(model), cached) }
        guard let made = runtime.executor(for: model, folder: storage.folder(for: model)) else {
            return (.apple, apple)
        }
        lock.withLock { downloadedExecutors[id] = made }
        return (.downloaded(model), made)
    }
}
