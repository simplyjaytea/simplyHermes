import Foundation
import HermesKit
import HermesUI
import Testing

/// The model behind Settings > On-device models (WP-65c), driven with scripted downloads and a stub runtime. The rules
/// for rows, buttons and deleting are tested in HermesKit; these tests check that the model keeps the screen current
/// and asks first before a big step.
@MainActor
struct OnDeviceModelsModelTests {
    @Test func rowsStartNotDownloadedAndTheAppleModelAnswers() {
        let fixture = OnDeviceFixture()
        #expect(fixture.model.rows.map(\.id) == ["alpha", "beta"])
        #expect(fixture.model.rows.allSatisfy { $0.state == .notDownloaded })
        #expect(fixture.model.appleModelIsInUse)
        #expect(fixture.model.usedBytes == 0)
        #expect(fixture.model.canRunDownloadedModels)
        #expect(fixture.model.question == nil)
    }

    @Test func downloadAsksFirstAndThenRuns() async throws {
        let fixture = OnDeviceFixture()
        fixture.startListening()
        defer { fixture.stopListening() }
        fixture.model.tap(.download, on: fixture.model.rows[0])
        let question = try #require(fixture.model.question)
        #expect(question.action == .download)
        #expect(question.model.id == "alpha")
        #expect(fixture.model.rows[0].state == .notDownloaded)
        fixture.model.confirm(question)
        #expect(fixture.model.question == nil)
        #expect(await eventually { fixture.model.rows[0].state == .downloaded })
        #expect(await eventually { fixture.model.usedBytes >= 110 })
    }

    @Test func useDoesNotAskAndTheAppleModelCanTakeOverAgain() async throws {
        let fixture = OnDeviceFixture()
        fixture.startListening()
        defer { fixture.stopListening() }
        try await fixture.download(row: 0)
        fixture.model.tap(.use, on: fixture.model.rows[0])
        #expect(fixture.model.question == nil)
        #expect(await eventually { fixture.model.rows[0].isSelected })
        #expect(!fixture.model.appleModelIsInUse)
        fixture.model.useAppleModel()
        #expect(await eventually { fixture.model.appleModelIsInUse })
        #expect(!fixture.model.rows[0].isSelected)
    }

    @Test func deleteAsksFirstAndThenFreesTheSpace() async throws {
        let fixture = OnDeviceFixture()
        fixture.startListening()
        defer { fixture.stopListening() }
        try await fixture.download(row: 0)
        #expect(await eventually { fixture.model.usedBytes >= 110 })
        fixture.model.tap(.delete, on: fixture.model.rows[0])
        let question = try #require(fixture.model.question)
        #expect(question.action == .delete)
        fixture.model.confirm(question)
        #expect(await eventually { fixture.model.rows[0].state == .notDownloaded })
        #expect(await eventually { fixture.model.usedBytes == 0 })
        #expect(fixture.model.errorText == nil)
    }

    @Test func cancelOfADownloadWithBytesAsksAndNamesTheAmount() async throws {
        let fixture = OnDeviceFixture(hanging: "model.safetensors")
        fixture.startListening()
        defer { fixture.stopListening() }
        fixture.model.tap(.download, on: fixture.model.rows[0])
        fixture.model.confirm(try #require(fixture.model.question))
        #expect(await eventually { fixture.model.rows[0].receivedBytes >= 50 })
        fixture.model.tap(.cancel, on: fixture.model.rows[0])
        let question = try #require(fixture.model.question)
        #expect(question.action == .cancel)
        #expect(question.receivedBytes >= 50)
        fixture.model.confirm(question)
        #expect(await eventually { fixture.model.rows[0].state == .notDownloaded })
    }

    @Test func pauseDoesNotAsk() async throws {
        let fixture = OnDeviceFixture(hanging: "model.safetensors")
        fixture.startListening()
        defer { fixture.stopListening() }
        fixture.model.tap(.download, on: fixture.model.rows[0])
        fixture.model.confirm(try #require(fixture.model.question))
        #expect(await eventually { fixture.model.rows[0].receivedBytes >= 50 })
        fixture.model.tap(.pause, on: fixture.model.rows[0])
        #expect(fixture.model.question == nil)
        #expect(
            await eventually {
                if case .paused = fixture.model.rows[0].state { true } else { false }
            })
    }

    @Test func aMemoryWarningShowsAfterRefresh() async throws {
        let fixture = OnDeviceFixture()
        fixture.startListening()
        defer { fixture.stopListening() }
        try await fixture.download(row: 0)
        fixture.model.tap(.use, on: fixture.model.rows[0])
        #expect(await eventually { fixture.model.rows[0].isSelected })

        await fixture.selection.handleMemoryWarning()
        fixture.model.refresh()

        #expect(fixture.model.isSuspendedByMemoryWarning)
        #expect(fixture.model.appleModelIsInUse)
        #expect(!fixture.model.rows[0].isSelected)
        #expect(fixture.model.rows[0].actions == [.use, .delete])
    }

    @Test func offlineChatOpensTheListAsASheet() {
        let fixture = OnDeviceFixture()
        #expect(!fixture.model.isListPresented)
        fixture.model.presentList()
        #expect(fixture.model.isListPresented)
    }
}

// MARK: Test doubles

private let alphaModel = OnDeviceModel(
    id: "alpha", displayName: "Alpha", summary: "The first.", repository: "test/alpha",
    revision: String(repeating: "a", count: 40),
    files: [OnDeviceModelFile("config.json", 10), OnDeviceModelFile("model.safetensors", 100)],
    license: "MIT", stopTokens: ["<end>"])

private let betaModel = OnDeviceModel(
    id: "beta", displayName: "Beta", summary: "The second.", repository: "test/beta",
    revision: String(repeating: "b", count: 40),
    files: [OnDeviceModelFile("config.json", 10), OnDeviceModelFile("model.safetensors", 50)],
    license: "MIT", isRecommended: true)

/// Polls until `condition` holds or ten seconds pass.
@MainActor
private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(10)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// The model, its manager and a folder in the temp directory that goes away with the fixture.
@MainActor
private final class OnDeviceFixture {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "on-device-models-ui-\(UUID().uuidString)", isDirectory: true)
    let selection: OnDeviceModelSelection
    let model: OnDeviceModelsModel
    private var listening: Task<Void, Never>?

    /// A file named `hanging` reports 40 bytes and then waits to be cancelled.
    init(hanging: String? = nil) {
        let root = root
        let catalog = OnDeviceModelCatalog(models: [alphaModel, betaModel])
        let storage = OnDeviceModelStorage(root: root.appendingPathComponent("models", isDirectory: true)) { _ in }
        let downloader = ScriptedModelDownloader(
            models: catalog.models, hanging: hanging, directory: root.appendingPathComponent("downloads"))
        let manager = OnDeviceModelManager(
            catalog: catalog, storage: storage, downloader: downloader, diskSpace: PlentyOfRoom(),
            reserveBytes: 100, progressStep: 1)
        let selection = OnDeviceModelSelection(
            apple: StubOnDeviceExecutor(), storage: storage, catalog: catalog, runtime: StubOnDeviceRuntime())
        self.selection = selection
        model = OnDeviceModelsModel(
            controller: OnDeviceModelController(manager: manager, selection: selection, catalog: catalog),
            storage: storage)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Keeps the rows current, as the screen does with `.task`.
    func startListening() {
        let model = model
        listening = Task { await model.run() }
    }

    func stopListening() {
        listening?.cancel()
    }

    /// Taps Download on a row, says yes, and waits until the files are on disk.
    func download(row index: Int) async throws {
        model.tap(.download, on: model.rows[index])
        model.confirm(try #require(model.question))
        let finished = await eventually { self.model.rows[index].state == .downloaded }
        try #require(finished)
    }
}

/// Writes a file of the catalog size for every request. A file named in `hanging` never finishes.
private final class ScriptedModelDownloader: ModelFileDownloader {
    private let sizes: [String: Int64]
    private let hanging: String?
    private let directory: URL

    init(models: [OnDeviceModel], hanging: String?, directory: URL) {
        var sizes: [String: Int64] = [:]
        for model in models {
            for file in model.files { sizes[model.downloadURL(for: file).path] = file.bytes }
        }
        self.sizes = sizes
        self.hanging = hanging
        self.directory = directory
    }

    func download(
        from url: URL, resumeData: Data?, progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        if url.lastPathComponent == hanging {
            progress(40)
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
            throw ModelFileDownloadCancelled()
        }
        let size = sizes[url.path] ?? 0
        progress(size)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("download-\(UUID().uuidString)")
        try Data(count: Int(size)).write(to: file)
        return file
    }
}

private struct PlentyOfRoom: DiskSpaceProviding {
    func availableBytes(at url: URL) -> Int64? { 1_000_000 }
}

private struct StubOnDeviceExecutor: LocalModelExecutor {
    var availability: LocalModelAvailability { .available }

    func respond(instructions: String, prompt: String) async throws -> String { prompt }
}

private struct StubOnDeviceRuntime: OnDeviceModelRuntime {
    func executor(for model: OnDeviceModel, folder: URL) -> (any LocalModelExecutor)? { StubOnDeviceExecutor() }

    func unloadAll() async {}
}
