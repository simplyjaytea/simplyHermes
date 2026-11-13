import Foundation

/// What the user picked in Settings > On-device models.
public enum OnDeviceModelChoice: Sendable, Hashable, Codable {
    /// The Apple on-device model. The default.
    case apple
    /// A downloaded model, by catalog id.
    case downloaded(String)
    /// No on-device model. Set when the model in use is deleted: nothing answers on the device, and the Apple model
    /// does not step in silently.
    case noModel
}

/// Why a downloaded model cannot answer.
public enum OnDeviceModelError: Error, Sendable, Equatable {
    /// The phone does not have enough free memory to load the model.
    case notEnoughMemory(needed: Int64, available: Int64)
    /// The chosen model is being checked or repaired, so it cannot answer yet.
    case notReady
    /// The model in use was deleted, and no other model was picked.
    case noModelChosen
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
///
/// The check is for a load, not for every answer. Once a model has answered, its weights are in memory and count
/// against the app, so the free figure is lower by about their size and a second check would refuse a model that
/// already fits. ``answer(with:_:)`` therefore checks only a model that is not known to be loaded, and the runtime
/// calls ``noteUnloaded()`` when it frees its models.
public final class OnDeviceMemoryGate: @unchecked Sendable {
    /// Bytes this app can still allocate, or nil when unknown (then loading is allowed).
    public let availableBytes: @Sendable () -> Int64?

    private let lock = NSLock()
    private var loadedID: String?
    /// Counts the unloads, so an answer that began before one does not mark its model as loaded after it.
    private var unloads = 0

    public init(availableBytes: @escaping @Sendable () -> Int64?) {
        self.availableBytes = availableBytes
    }

    /// Throws ``OnDeviceModelError/notEnoughMemory(needed:available:)`` when the estimate does not fit. A model that is
    /// known to be loaded needs no new room, so it passes.
    public func check(_ model: OnDeviceModel) throws {
        let isLoaded = lock.withLock { loadedID == model.id }
        guard !isLoaded, let available = availableBytes(), available < model.estimatedMemoryBytes else { return }
        throw OnDeviceModelError.notEnoughMemory(needed: model.estimatedMemoryBytes, available: available)
    }

    /// Runs one answer of `model`: checks the memory first, and afterwards remembers that the model is loaded. Nothing
    /// is remembered when the answer throws or when the models were unloaded while it ran.
    public func answer<Reply>(with model: OnDeviceModel, _ body: () async throws -> Reply) async throws -> Reply {
        try check(model)
        let epoch = lock.withLock { unloads }
        let reply = try await body()
        lock.withLock {
            if unloads == epoch { loadedID = model.id }
        }
        return reply
    }

    /// The runtime freed its models, so the next answer loads again and is checked again.
    public func noteUnloaded() {
        lock.withLock {
            loadedID = nil
            unloads += 1
        }
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
public final class OnDeviceModelSelection: LocalModelExecutor, LocalChatAnswerer, @unchecked Sendable {
    /// Which model would answer right now.
    public enum Route: Sendable, Equatable {
        case apple
        case downloaded(OnDeviceModel)
        /// No on-device model: the model in use was deleted. Nothing answers on the device.
        case noModel
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
    /// Models whose weights were loaded by ``prepare()`` and not unloaded since.
    private var prepared: Set<String> = []
    /// Models ``prepare()`` is loading now.
    private var loading: Set<String> = []
    /// The free memory a refusal reported, for the reason shown when the model was refused (WP-9).
    private var lastAvailableBytes: Int64?

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

    /// Which model answers right now, after the fallbacks. It is `.noModel` when the model in use was deleted.
    public var route: Route {
        resolve().route
    }

    /// The model a new Local chat would answer with, or nil when none can answer now (the feature is off, or the
    /// model is not ready). The New chat menu names the model only when this is not nil.
    public var answeringModel: ModelIdentity? {
        guard case .available = availability else { return nil }
        return Self.identity(of: route)
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
            prepared = []
        }
        await runtime?.unloadAll()
    }

    /// Call before a model's files are deleted. Unloads it, forgets its executor, and falls back to the Apple model
    /// when it was the one in use.
    public func modelWillBeDeleted(_ id: String) async {
        let wasInUse = lock.withLock { () -> Bool in
            downloadedExecutors[id] = nil
            prepared.remove(id)
            return savedChoice == .downloaded(id)
        }
        if wasInUse { setChoice(.noModel) }
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
        } catch OnDeviceModelError.notEnoughMemory(_, let available) where route != .apple {
            lock.withLock { lastAvailableBytes = available }
            await handleMemoryWarning()
            return try await apple.respond(instructions: instructions, prompt: prompt)
        }
    }

    /// Answers like ``respond(instructions:prompt:)`` and names the model that wrote the reply (WP-7). After a memory
    /// fallback the name is the Apple model's, because that is the model that answered.
    public func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
        let (route, executor) = resolve()
        do {
            let text = try await executor.respond(instructions: instructions, prompt: prompt)
            // The no-model executor throws above. This guard keeps a reply from ever being attributed to no model.
            guard let identity = Self.identity(of: route) else { throw OnDeviceModelError.noModelChosen }
            return LocalAnswer(text: text, answeredBy: identity)
        } catch OnDeviceModelError.notEnoughMemory(_, let available) where route != .apple {
            lock.withLock { lastAvailableBytes = available }
            await handleMemoryWarning()
            let text = try await apple.respond(instructions: instructions, prompt: prompt)
            return LocalAnswer(text: text, answeredBy: .apple)
        }
    }

    // MARK: Status (WP-9)

    /// Why the model the user chose is not the one answering, when the Apple model answers in its place. Nil when nothing
    /// was substituted. The reasons are the ones a pill can show: no runtime, not enough memory, files not on the phone.
    public var substitution: LocalModelFailure? {
        let (choice, suspended, available) = lock.withLock { (savedChoice, suspendedByMemory, lastAvailableBytes) }
        guard case .downloaded(let id) = choice else { return nil }
        guard let model = catalog.model(id: id), storage.isDownloaded(model) else {
            return .loadError("The model's files are not on this iPhone.")
        }
        if suspended {
            return .notEnoughMemory(needed: model.estimatedMemoryBytes, available: available ?? 0)
        }
        guard let runtime else { return .runtimeUnavailable }
        if storage.isAwaitingCheck(model) { return nil }
        let known = lock.withLock { downloadedExecutors[id] != nil }
        if !known, runtime.executor(for: model, folder: storage.folder(for: model)) == nil {
            return .runtimeUnavailable
        }
        return nil
    }

    /// What the pill reads for the on-device model: which model will answer, and why another cannot (WP-9). It never
    /// names the Apple model as ready when the user chose another one and that one cannot run: it says why.
    public var status: LocalModelStatus {
        guard isEnabled() else { return .off }
        let choice = lock.withLock { savedChoice }
        switch choice {
        case .noModel:
            return .noModel
        case .apple:
            return Self.status(of: apple.availability)
        case .downloaded(let id):
            guard let model = catalog.model(id: id) else { return .noModel }
            let identity = ModelIdentity.downloaded(id: model.id, displayName: model.displayName)
            if storage.isAwaitingCheck(model) { return .verifying }
            if let reason = substitution { return .failed(identity, reason: reason) }
            let (isLoading, isPrepared) = lock.withLock { (loading.contains(id), prepared.contains(id)) }
            if isLoading { return .loading(model) }
            return isPrepared ? .ready(answeredBy: identity) : .notLoaded(model)
        }
    }

    private static func status(of availability: LocalModelAvailability) -> LocalModelStatus {
        switch availability {
        case .available: .ready(answeredBy: .apple)
        case .unavailable(.switchedOff): .off
        case .unavailable: .noModel
        }
    }

    /// Loads the chosen model now and returns the status after: ready, or why it cannot answer (WP-9). The Apple model
    /// has nothing to load. A failure is a status, not a thrown error, and it never falls back to another model.
    @discardableResult
    public func prepare() async -> LocalModelStatus {
        guard isEnabled(), case .downloaded(let id) = lock.withLock({ savedChoice }), let model = catalog.model(id: id)
        else { return status }
        guard substitution == nil, !storage.isAwaitingCheck(model) else { return status }
        let identity = ModelIdentity.downloaded(id: model.id, displayName: model.displayName)
        let (_, executor) = resolve()
        lock.withLock { _ = loading.insert(id) }
        var failure: LocalModelStatus?
        do {
            try await executor.load()
            lock.withLock { _ = prepared.insert(id) }
        } catch OnDeviceModelError.notEnoughMemory(let needed, let available) {
            lock.withLock { lastAvailableBytes = available }
            failure = .failed(identity, reason: .notEnoughMemory(needed: needed, available: available))
        } catch {
            failure = .failed(identity, reason: .loadError("\(error)"))
        }
        // Loading ends before the status is read, so the answer is ready or failed, never still loading.
        lock.withLock { _ = loading.remove(id) }
        return failure ?? status
    }

    /// The model that names a reply on `route`. Nil for the no-model route: nothing answers there, so no reply may be
    /// attributed to any model, and Apple is not a default.
    static func identity(of route: Route) -> ModelIdentity? {
        switch route {
        case .apple: .apple
        case .downloaded(let model): .downloaded(id: model.id, displayName: model.displayName)
        case .noModel: nil
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
            if previous != choice { prepared = [] }
            return previous != choice
        }
        storage.saveChoice(choice)
        return changed
    }

    private func resolve() -> (route: Route, executor: any LocalModelExecutor) {
        let (choice, suspended) = lock.withLock { (savedChoice, suspendedByMemory) }
        // The model in use was deleted: nothing answers on the device, and Apple does not step in.
        if choice == .noModel { return (.noModel, UnavailableExecutor(reason: .noModelChosen, error: .noModelChosen)) }
        guard !suspended, let runtime, case .downloaded(let id) = choice, let model = catalog.model(id: id) else {
            return (.apple, apple)
        }
        // A model whose earlier files are being checked stays the choice. It is not ready, and Apple does not answer
        // in its place.
        if storage.isAwaitingCheck(model) {
            return (.downloaded(model), UnavailableExecutor(reason: .notReady, error: .notReady))
        }
        guard storage.isDownloaded(model) else { return (.apple, apple) }
        if let cached = lock.withLock({ downloadedExecutors[id] }) { return (.downloaded(model), cached) }
        guard let made = runtime.executor(for: model, folder: storage.folder(for: model)) else {
            return (.apple, apple)
        }
        lock.withLock { downloadedExecutors[id] = made }
        return (.downloaded(model), made)
    }
}

/// Stands in for the on-device model when none can answer: a model being checked, or none chosen. It never answers.
private struct UnavailableExecutor: LocalModelExecutor {
    let reason: LocalModelUnavailable
    let error: OnDeviceModelError

    var availability: LocalModelAvailability { .unavailable(reason) }

    func respond(instructions: String, prompt: String) async throws -> String {
        throw error
    }
}
