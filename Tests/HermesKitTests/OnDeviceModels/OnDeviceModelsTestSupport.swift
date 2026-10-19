import Foundation

@testable import HermesKit

/// Two tiny models, so tests move bytes in the tens, not gigabytes.
enum TestModels {
    static let alpha = OnDeviceModel(
        id: "alpha", displayName: "Alpha", summary: "The first.", repository: "test/alpha",
        revision: String(repeating: "a", count: 40),
        files: [OnDeviceModelFile("config.json", 10), OnDeviceModelFile("model.safetensors", 100)],
        license: "MIT", stopTokens: ["<end>"])
    static let beta = OnDeviceModel(
        id: "beta", displayName: "Beta", summary: "The second.", repository: "test/beta",
        revision: String(repeating: "b", count: 40),
        files: [OnDeviceModelFile("config.json", 10), OnDeviceModelFile("model.safetensors", 50)],
        license: "MIT", isRecommended: true)
    static let catalog = OnDeviceModelCatalog(models: [alpha, beta])
}

/// A folder in the temp directory that is deleted when the test ends, with a storage rooted in it.
final class TestEnvironment: @unchecked Sendable {
    let root: URL
    let storage: OnDeviceModelStorage
    private let recorder: Recorder

    init() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "on-device-models-\(UUID().uuidString)", isDirectory: true)
        let recorder = Recorder()
        self.root = root
        self.recorder = recorder
        storage = OnDeviceModelStorage(root: root.appendingPathComponent("models", isDirectory: true)) { url in
            recorder.add(url)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Every folder the storage marked as excluded from backup, in order.
    var excludedFromBackup: [URL] { recorder.urls }

    /// Writes a file of `bytes` zero bytes in the temp area, as a downloader would leave it.
    func makeTemporaryFile(bytes: Int64) throws -> URL {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("tmp-\(UUID().uuidString)")
        try Data(count: Int(bytes)).write(to: url)
        return url
    }

    /// Puts a whole model on disk the way a finished download does.
    func installFinished(_ model: OnDeviceModel) throws {
        try storage.preparePartialFolder(for: model)
        for file in model.files {
            try storage.store(makeTemporaryFile(bytes: file.bytes), as: file, of: model)
        }
        try storage.complete(model)
    }

    private final class Recorder: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [URL] = []

        func add(_ url: URL) { lock.withLock { stored.append(url) } }
        var urls: [URL] { lock.withLock { stored } }
    }
}

/// Scripts what each file download does. Files not scripted succeed.
final class MockModelDownloader: ModelFileDownloader, @unchecked Sendable {
    enum Behavior {
        case succeed
        /// Succeeds, but the file has a different size than the catalog says.
        case wrongSize(Int64)
        case failStatus(Int)
        case failNetwork(String, resumeData: Data?)
        case failFileSystem(String)
        /// Reports `bytes` received, then waits until the task is cancelled and throws with resume data.
        case hang(bytes: Int64)
    }

    struct Call: Equatable {
        let url: URL
        let resumeData: Data?

        var file: String { url.lastPathComponent }
    }

    private let lock = NSLock()
    private var scripts: [String: [Behavior]] = [:]
    private var recorded: [Call] = []
    private let sizes: [String: Int64]
    private let directory: URL

    init(models: [OnDeviceModel], directory: URL) {
        var sizes: [String: Int64] = [:]
        for model in models {
            for file in model.files { sizes[model.downloadURL(for: file).path] = file.bytes }
        }
        self.sizes = sizes
        self.directory = directory
    }

    /// The next downloads of `file` in `model` do these things in order; after that they succeed.
    func script(_ model: OnDeviceModel, _ file: String, _ behaviors: Behavior...) {
        guard let entry = model.files.first(where: { $0.path == file }) else { return }
        lock.withLock { scripts[model.downloadURL(for: entry).path, default: []].append(contentsOf: behaviors) }
    }

    var calls: [Call] { lock.withLock { recorded } }
    var calledFiles: [String] { calls.map(\.file) }

    /// The calls made for one model's files.
    func calls(for model: OnDeviceModel) -> [Call] {
        calls.filter { $0.url.path.hasPrefix("/\(model.repository)/") }
    }

    /// The resume data a hung download returns when it is cancelled.
    static func resumeData(for file: String) -> Data { Data("resume-\(file)".utf8) }

    func download(
        from url: URL, resumeData: Data?, progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        let file = url.lastPathComponent
        let size = sizes[url.path] ?? 0
        let behavior: Behavior = lock.withLock {
            recorded.append(Call(url: url, resumeData: resumeData))
            guard var script = scripts[url.path], !script.isEmpty else { return .succeed }
            let next = script.removeFirst()
            scripts[url.path] = script
            return next
        }
        switch behavior {
        case .succeed:
            progress(size / 2)
            progress(size)
            return try makeFile(bytes: size)
        case .wrongSize(let bytes):
            return try makeFile(bytes: bytes)
        case .failStatus(let status):
            throw ModelFileDownloadError.badStatus(status)
        case .failNetwork(let message, let data):
            throw ModelFileDownloadError.network(message, resumeData: data)
        case .failFileSystem(let message):
            throw ModelFileDownloadError.fileSystem(message)
        case .hang(let bytes):
            progress(bytes)
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            throw ModelFileDownloadCancelled(resumeData: Self.resumeData(for: file))
        }
    }

    private func makeFile(bytes: Int64) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("download-\(UUID().uuidString)")
        try Data(count: Int(bytes)).write(to: url)
        return url
    }
}

struct FixedDiskSpace: DiskSpaceProviding {
    var bytes: Int64?

    func availableBytes(at url: URL) -> Int64? { bytes }
}

/// Answers every call with its name, and can be told to fail.
final class StubExecutor: LocalModelExecutor, @unchecked Sendable {
    let name: String
    private let lock = NSLock()
    private var currentAvailability: LocalModelAvailability = .available
    private var currentFailure: (any Error)?
    private var recorded: [String] = []

    init(name: String) {
        self.name = name
    }

    var availability: LocalModelAvailability {
        get { lock.withLock { currentAvailability } }
        set { lock.withLock { currentAvailability = newValue } }
    }

    var failure: (any Error)? {
        get { lock.withLock { currentFailure } }
        set { lock.withLock { currentFailure = newValue } }
    }

    var prompts: [String] { lock.withLock { recorded } }

    func respond(instructions: String, prompt: String) async throws -> String {
        lock.withLock { recorded.append(prompt) }
        if let failure { throw failure }
        return "\(name): \(prompt)"
    }
}

/// A switch a test can flip while code under test reads it from another task.
final class TestFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Bool

    init(_ value: Bool) {
        current = value
    }

    var value: Bool {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

struct TestFailure: Error, Equatable {
    var message = "boom"
}

/// Hands out stub executors for the models it knows and counts unloads.
final class StubRuntime: OnDeviceModelRuntime, @unchecked Sendable {
    private let lock = NSLock()
    private var executors: [String: StubExecutor]
    private var unloads = 0
    private var requested: [String] = []
    private var unloadProbe: (@Sendable () -> Void)?

    init(executors: [String: StubExecutor] = [:]) {
        self.executors = executors
    }

    var unloadCount: Int { lock.withLock { unloads } }
    var requestedModels: [String] { lock.withLock { requested } }

    /// Runs inside every `unloadAll()`, so a test can look at the world at the moment of the unload.
    func onUnload(_ probe: @escaping @Sendable () -> Void) {
        lock.withLock { unloadProbe = probe }
    }

    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? {
        lock.withLock {
            requested.append(model.id)
            return executors[model.id]
        }
    }

    func unloadAll() async {
        let probe = lock.withLock { () -> (@Sendable () -> Void)? in
            unloads += 1
            return unloadProbe
        }
        probe?()
    }
}

/// Polls until `condition` holds or `timeout` passes. Returns whether it held.
func waitUntil(
    timeout: Duration = .seconds(10), _ condition: @Sendable () async -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(3))
    }
    return await condition()
}

/// Collects the manager's updates so a test can look at the order they came in.
final class UpdateRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [OnDeviceModelUpdate] = []
    private var task: Task<Void, Never>?

    init(_ stream: AsyncStream<OnDeviceModelUpdate>) {
        task = Task { [weak self] in
            for await update in stream { self?.lock.withLock { self?.stored.append(update) } }
        }
    }

    deinit { task?.cancel() }

    var updates: [OnDeviceModelUpdate] { lock.withLock { stored } }

    func states(of id: String) -> [OnDeviceModelState] {
        updates.filter { $0.id == id }.map(\.state)
    }
}
