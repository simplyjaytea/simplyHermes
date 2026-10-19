import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsControllerTests {
    private let alpha = TestModels.alpha
    private let beta = TestModels.beta

    private struct Setup {
        let env: TestEnvironment
        let downloader: MockModelDownloader
        let manager: OnDeviceModelManager
        let runtime: StubRuntime
        let selection: OnDeviceModelSelection
        let controller: OnDeviceModelController

        init(memory: Int64? = nil, hasRuntime: Bool = true) {
            let env = TestEnvironment()
            let downloader = MockModelDownloader(
                models: TestModels.catalog.models, directory: env.root.appendingPathComponent("downloads"))
            let manager = OnDeviceModelManager(
                catalog: TestModels.catalog, storage: env.storage, downloader: downloader,
                diskSpace: FixedDiskSpace(bytes: 1_000_000), reserveBytes: 100, progressStep: 1)
            let runtime = StubRuntime(executors: [
                "alpha": StubExecutor(name: "alpha"), "beta": StubExecutor(name: "beta"),
            ])
            let selection = OnDeviceModelSelection(
                apple: StubExecutor(name: "apple"), storage: env.storage, catalog: TestModels.catalog,
                runtime: hasRuntime ? runtime : nil)
            self.env = env
            self.downloader = downloader
            self.manager = manager
            self.runtime = runtime
            self.selection = selection
            controller = OnDeviceModelController(
                manager: manager, selection: selection, catalog: TestModels.catalog, availableMemory: { memory })
        }

        func waitForDownloaded(_ id: String) async -> Bool {
            let manager = manager
            return await waitUntil { await manager.state(of: id) == .downloaded }
        }

        func waitForFailure(_ id: String) async -> Bool {
            let manager = manager
            return await waitUntil {
                if case .failed = await manager.state(of: id) { true } else { false }
            }
        }

        /// Waits until the download shows at least `bytes` received.
        func waitForProgress(_ id: String, _ bytes: Int64) async -> Bool {
            let manager = manager
            return await waitUntil {
                if case .downloading(let progress) = await manager.state(of: id) {
                    progress.receivedBytes >= bytes
                } else {
                    false
                }
            }
        }
    }

    @Test func rowsFollowTheCatalogOrderAndTheStatesGiven() {
        let setup = Setup()
        let paused = OnDeviceModelState.paused(OnDeviceModelProgress(receivedBytes: 5, totalBytes: 110))
        let rows = setup.controller.rows(states: ["beta": paused])
        #expect(rows.map(\.id) == ["alpha", "beta"])
        #expect(rows.map(\.state) == [.notDownloaded, paused])
        #expect(rows.allSatisfy { !$0.isSelected && $0.canRun })
        #expect(setup.controller.appleModelIsInUse)
    }

    @Test func aDeviceWithoutARuntimeCannotRunDownloadedModels() {
        let setup = Setup(hasRuntime: false)
        #expect(setup.controller.rows(states: [:]).allSatisfy { !$0.canRun })
    }

    @Test func theMemoryFigureReachesEveryRow() {
        let setup = Setup(memory: 1)
        let rows = setup.controller.rows(states: ["alpha": .downloaded, "beta": .downloaded])
        #expect(rows.allSatisfy { $0.availableMemoryBytes == 1 && $0.mayNotFitInMemory })
    }

    @Test func downloadingThenUsingAModelMakesItTheOneInUse() async throws {
        let setup = Setup()
        try await setup.controller.perform(.download, on: alpha)
        #expect(await setup.waitForDownloaded("alpha"))
        try await setup.controller.perform(.use, on: alpha)

        let rows = setup.controller.rows(states: await setup.manager.allStates())
        #expect(rows[0].isSelected)
        #expect(rows[0].actions == [.delete])
        #expect(rows[1].actions == [.download])
        #expect(!setup.controller.appleModelIsInUse)

        await setup.controller.useAppleModel()
        #expect(setup.controller.appleModelIsInUse)
        #expect(setup.controller.rows(states: ["alpha": .downloaded])[0].actions == [.use, .delete])
    }

    @Test func afterAMemoryWarningTheModelOffersUseAgain() async throws {
        let setup = Setup()
        try setup.env.installFinished(alpha)
        try await setup.controller.perform(.use, on: alpha)
        await setup.selection.handleMemoryWarning()

        let row = setup.controller.rows(states: ["alpha": .downloaded])[0]
        #expect(!row.isSelected)
        #expect(row.actions == [.use, .delete])
        #expect(setup.controller.appleModelIsInUse)
    }

    @Test func pauseResumeAndCancelReachTheManager() async throws {
        let setup = Setup()
        setup.downloader.script(alpha, "model.safetensors", .hang(bytes: 20))
        try await setup.controller.perform(.download, on: alpha)
        #expect(await setup.waitForProgress("alpha", 30))

        try await setup.controller.perform(.pause, on: alpha)
        let state = await setup.manager.state(of: "alpha")
        guard case .paused = state else {
            Issue.record("expected a paused download, got \(state)")
            return
        }

        try await setup.controller.perform(.resume, on: alpha)
        #expect(await setup.waitForDownloaded("alpha"))

        try await setup.controller.perform(.download, on: beta)
        #expect(await setup.waitForDownloaded("beta"))
        try await setup.controller.perform(.delete, on: beta)
        #expect(await setup.manager.state(of: "beta") == .notDownloaded)
    }

    @Test func aFailedDownloadStartsAgainOnRetry() async throws {
        let setup = Setup()
        setup.downloader.script(alpha, "config.json", .failStatus(500))
        try await setup.controller.perform(.download, on: alpha)
        #expect(await setup.waitForFailure("alpha"))
        try await setup.controller.perform(.retry, on: alpha)
        #expect(await setup.waitForDownloaded("alpha"))
    }

    @Test func cancelDiscardsTheDownload() async throws {
        let setup = Setup()
        setup.downloader.script(alpha, "model.safetensors", .hang(bytes: 20))
        try await setup.controller.perform(.download, on: alpha)
        #expect(await setup.waitForProgress("alpha", 30))
        try await setup.controller.perform(.cancel, on: alpha)
        #expect(await setup.manager.state(of: "alpha") == .notDownloaded)
        #expect(setup.env.storage.usedBytes() == 0)
    }

    @Test func deletingTheModelInUseUnloadsItBeforeTheFilesGoAndFallsBackToApple() async throws {
        let setup = Setup()
        try setup.env.installFinished(alpha)
        await setup.manager.reload()
        try await setup.controller.perform(.use, on: alpha)

        let folder = setup.env.storage.folder(for: alpha)
        let filesWereThereAtUnload = TestFlag(false)
        setup.runtime.onUnload { filesWereThereAtUnload.value = FileManager.default.fileExists(atPath: folder.path) }

        try await setup.controller.perform(.delete, on: alpha)

        #expect(filesWereThereAtUnload.value)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
        #expect(await setup.manager.state(of: "alpha") == .notDownloaded)
        #expect(setup.selection.choice == .apple)
        #expect(setup.controller.appleModelIsInUse)
    }
}
