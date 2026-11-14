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
    /// The chosen model's files are not on this iPhone (deleted, not finished).
    case filesMissing
    /// This iPhone cannot run the chosen model: the app has no runtime, or the runtime refuses the model.
    case runtimeUnavailable
    /// The chosen model is not in the catalog any more.
    case modelNotOffered
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
/// current choice: it looks at the choice on every call. The app never switches model by itself. The Apple model
/// answers only when the user chose it. When the user chose a downloaded model and it cannot answer, nothing answers:
/// the call throws an ``OnDeviceModelError`` and ``availability`` says why. That happens when
/// - the picked model is not on the phone (deleted, not finished) or no longer in the catalog,
/// - the runtime cannot run it on this device,
/// - or loading the model fails for lack of memory. A memory warning (plan WP-65c) unloads the model, and the next
///   question tries to load it again.
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
    /// Set by a memory warning or a refused load, for the status only. It does not change which model answers: the
    /// next question tries to load the chosen model again. A successful load or a new pick clears it.
    private var suspendedByMemory = false
    private var downloadedExecutors: [String: any LocalModelExecutor] = [:]
    /// Models whose weights were loaded by ``prepare()`` and not unloaded since.
    private var prepared: Set<String> = []
    /// Models ``prepare()`` is loading now.
    private var loading: Set<String> = []
    /// The free memory a refusal reported, for the reason shown when the model was refused (WP-9).
    private var lastAvailableBytes: Int64?

    /// `runtime` is nil where nothing can run a downloaded model: then a downloaded choice cannot answer.
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
        // No file means a fresh install, which starts on the Apple model. A file that cannot be read may have held a
        // downloaded choice, so it leaves no model chosen instead of turning into the Apple model.
        savedChoice = storage.loadChoice() ?? (storage.hasUnreadableChoice() ? .noModel : .apple)
    }

    // MARK: Reading

    /// What the user picked. It can differ from ``route``.
    public var choice: OnDeviceModelChoice {
        lock.withLock { savedChoice }
    }

    /// Which model would answer right now. It is `.noModel` when the model in use was deleted or is not offered.
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

    /// True after a memory warning or a load refused for lack of memory, until the chosen model loads again. Nothing
    /// answers in its place.
    public var isSuspendedByMemoryWarning: Bool {
        lock.withLock { suspendedByMemory }
    }

    // MARK: Changing

    /// Saves the choice. Picking a model again after a memory warning lets it load again. A different choice unloads
    /// the old model first: two models in memory at once would be the surest way to a memory warning.
    public func select(_ choice: OnDeviceModelChoice) async {
        if setChoice(choice) { await runtime?.unloadAll() }
    }

    /// iOS sent a memory warning: unload the downloaded model. The chosen model stays chosen and loads again on the next
    /// question; the Apple model does not take over.
    public func handleMemoryWarning() async {
        lock.withLock {
            if case .downloaded = savedChoice { suspendedByMemory = true }
            prepared = []
        }
        await runtime?.unloadAll()
    }

    /// Call before a model's files are deleted. Unloads it, forgets its executor, and leaves no model chosen when it was
    /// the one in use.
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
        try await run(instructions: instructions, prompt: prompt).text
    }

    /// Answers like ``respond(instructions:prompt:)`` and names the model that wrote the reply (WP-7).
    public func answer(instructions: String, prompt: String) async throws -> LocalAnswer {
        let (text, route) = try await run(instructions: instructions, prompt: prompt)
        // The no-model executor throws above. This guard keeps a reply from ever being attributed to no model.
        guard let identity = Self.identity(of: route) else { throw OnDeviceModelError.noModelChosen }
        return LocalAnswer(text: text, answeredBy: identity)
    }

    /// Asks the model that ``resolve()`` picked, once. A refused load is rethrown: no other model is asked.
    private func run(instructions: String, prompt: String) async throws -> (text: String, route: Route) {
        let (route, executor) = resolve()
        do {
            let text = try await executor.respond(instructions: instructions, prompt: prompt)
            noteAnswered(route)
            return (text, route)
        } catch OnDeviceModelError.notEnoughMemory(let needed, let available) where route != .apple {
            await noteMemoryRefusal(available: available)
            throw OnDeviceModelError.notEnoughMemory(needed: needed, available: available)
        }
    }

    private func noteAnswered(_ route: Route) {
        guard case .downloaded = route else { return }
        lock.withLock { suspendedByMemory = false }
    }

    private func noteMemoryRefusal(available: Int64) async {
        lock.withLock { lastAvailableBytes = available }
        await handleMemoryWarning()
    }

    // MARK: Status (WP-9)

    /// Why the model the user chose cannot answer, or nil when it can. Nothing answers in its place. The reasons are the
    /// ones a pill can show: no runtime, not enough memory, files not on the phone, model not offered.
    public var cannotAnswerReason: LocalModelFailure? {
        let (choice, suspended, available) = lock.withLock { (savedChoice, suspendedByMemory, lastAvailableBytes) }
        guard case .downloaded(let id) = choice else { return nil }
        if let blocked = blockingFailure() { return blocked }
        guard suspended, let model = catalog.model(id: id) else { return nil }
        return .notEnoughMemory(needed: model.estimatedMemoryBytes, available: available ?? 0)
    }

    /// The failure that no retry fixes: the chosen model's files, runtime or catalog entry. Nil when none, and while the
    /// files are being checked.
    private func blockingFailure() -> LocalModelFailure? {
        (resolve().executor as? UnavailableExecutor)?.failure
    }

    /// What the pill reads for the on-device model: which model will answer, and why it cannot (WP-9). It never names
    /// the Apple model as ready when the user chose another one and that one cannot run: it says why.
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
            if let reason = cannotAnswerReason { return .failed(identity, reason: reason) }
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
    /// has nothing to load. A failure is a status, not a thrown error, and no other model answers instead.
    @discardableResult
    public func prepare() async -> LocalModelStatus {
        guard isEnabled(), case .downloaded(let id) = lock.withLock({ savedChoice }), let model = catalog.model(id: id)
        else { return status }
        guard blockingFailure() == nil, !storage.isAwaitingCheck(model) else { return status }
        let identity = ModelIdentity.downloaded(id: model.id, displayName: model.displayName)
        let (_, executor) = resolve()
        lock.withLock { _ = loading.insert(id) }
        var failure: LocalModelStatus?
        do {
            try await executor.load()
            lock.withLock {
                _ = prepared.insert(id)
                suspendedByMemory = false
            }
        } catch OnDeviceModelError.notEnoughMemory(let needed, let available) {
            lock.withLock {
                lastAvailableBytes = available
                suspendedByMemory = true
            }
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

    /// Stores the choice and clears the memory report. Returns true when the choice changed.
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
        let choice = lock.withLock { savedChoice }
        switch choice {
        case .apple:
            return (.apple, apple)
        // The model in use was deleted: nothing answers on the device, and Apple does not step in.
        case .noModel:
            return (.noModel, UnavailableExecutor(reason: .noModelChosen, error: .noModelChosen))
        case .downloaded(let id):
            return resolveDownloaded(id)
        }
    }

    /// A downloaded choice never resolves to the Apple model. When the model cannot answer, the executor throws why.
    private func resolveDownloaded(_ id: String) -> (route: Route, executor: any LocalModelExecutor) {
        guard let model = catalog.model(id: id) else {
            let failure = LocalModelFailure.loadError("This model is no longer offered.")
            return (.noModel, UnavailableExecutor(failure: failure, error: .modelNotOffered))
        }
        // A model whose earlier files are being checked stays the choice. It is not ready.
        if storage.isAwaitingCheck(model) {
            return (.downloaded(model), UnavailableExecutor(reason: .notReady, error: .notReady))
        }
        guard storage.isDownloaded(model) else {
            let failure = LocalModelFailure.loadError("The model's files are not on this iPhone.")
            return (.downloaded(model), UnavailableExecutor(failure: failure, error: .filesMissing))
        }
        guard let runtime else {
            return (.downloaded(model), UnavailableExecutor(failure: .runtimeUnavailable, error: .runtimeUnavailable))
        }
        if let cached = lock.withLock({ downloadedExecutors[id] }) { return (.downloaded(model), cached) }
        guard let made = runtime.executor(for: model, folder: storage.folder(for: model)) else {
            return (.downloaded(model), UnavailableExecutor(failure: .runtimeUnavailable, error: .runtimeUnavailable))
        }
        lock.withLock { downloadedExecutors[id] = made }
        return (.downloaded(model), made)
    }
}

/// Stands in for the on-device model when none can answer: a model being checked, one that cannot run, or none chosen.
/// It never answers.
private struct UnavailableExecutor: LocalModelExecutor {
    let reason: LocalModelUnavailable
    let error: OnDeviceModelError
    /// Why the chosen model cannot answer, for the status. Nil for a model being checked and for no model.
    let failure: LocalModelFailure?

    init(reason: LocalModelUnavailable, error: OnDeviceModelError) {
        self.reason = reason
        self.error = error
        failure = nil
    }

    init(failure: LocalModelFailure, error: OnDeviceModelError) {
        reason = .chosenModelCannotAnswer(failure)
        self.error = error
        self.failure = failure
    }

    var availability: LocalModelAvailability { .unavailable(reason) }

    func respond(instructions: String, prompt: String) async throws -> String {
        throw error
    }
}
