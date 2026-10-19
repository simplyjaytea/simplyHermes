import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsManagerTests {
    private let alpha = TestModels.alpha
    private let beta = TestModels.beta

    /// A manager over a fresh temp folder, with a scripted downloader and a phone that has `freeBytes` left.
    private struct Harness {
        let env: TestEnvironment
        let downloader: MockModelDownloader
        let manager: OnDeviceModelManager

        init(freeBytes: Int64? = 1_000_000, reserve: Int64 = 100, env: TestEnvironment = TestEnvironment()) {
            self.env = env
            downloader = MockModelDownloader(
                models: TestModels.catalog.models, directory: env.root.appendingPathComponent("downloads"))
            manager = OnDeviceModelManager(
                catalog: TestModels.catalog, storage: env.storage, downloader: downloader,
                diskSpace: FixedDiskSpace(bytes: freeBytes), reserveBytes: reserve, progressStep: 1)
        }

        func wait(for id: String, _ matches: @escaping @Sendable (OnDeviceModelState) -> Bool) async -> Bool {
            let manager = manager
            return await waitUntil { matches(await manager.state(of: id)) }
        }

        func waitForDownloaded(_ id: String) async -> Bool {
            await wait(for: id) { $0 == .downloaded }
        }

        func waitForFailure(_ id: String) async -> Bool {
            await wait(for: id) { state in
                if case .failed = state { true } else { false }
            }
        }

        /// Waits until the download shows at least `bytes` received.
        func waitForProgress(_ id: String, _ bytes: Int64) async -> Bool {
            await wait(for: id) { state in
                if case .downloading(let progress) = state { progress.receivedBytes >= bytes } else { false }
            }
        }
    }

    private func progress(_ received: Int64, of total: Int64) -> OnDeviceModelProgress {
        OnDeviceModelProgress(receivedBytes: received, totalBytes: total)
    }

    // MARK: Downloading

    @Test func aDownloadFetchesEveryFileAndMarksTheModelDownloaded() async {
        let harness = Harness()
        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
        #expect(harness.env.storage.isDownloaded(alpha))
        #expect(harness.downloader.calledFiles == ["config.json", "model.safetensors"])
        #expect(harness.downloader.calls.allSatisfy { $0.resumeData == nil })
        #expect(await harness.manager.state(of: "beta") == .notDownloaded)
    }

    @Test func updatesTellTheStoryOfADownload() async {
        let harness = Harness()
        let recorder = UpdateRecorder(await harness.manager.updates())
        await harness.manager.start("alpha")
        #expect(await waitUntil { recorder.states(of: "alpha").last == .downloaded })
        let states = recorder.states(of: "alpha")
        #expect(states.first == .notDownloaded)
        #expect(states.contains(.queued))
        var received: [Int64] = []
        for case .downloading(let progress) in states {
            #expect(progress.totalBytes == 110)
            received.append(progress.receivedBytes)
        }
        #expect(received == received.sorted())
        #expect(received.last == 110)
        #expect(recorder.states(of: "beta") == [.notDownloaded])
    }

    @Test func updatesStartWithTheCurrentStateOfEveryModel() async throws {
        let harness = Harness()
        try harness.env.installFinished(alpha)
        await harness.manager.reload()
        let recorder = UpdateRecorder(await harness.manager.updates())
        #expect(await waitUntil { recorder.updates.count == 2 })
        #expect(
            recorder.updates == [
                OnDeviceModelUpdate(id: "alpha", state: .downloaded),
                OnDeviceModelUpdate(id: "beta", state: .notDownloaded),
            ])
    }

    @Test func startingAModelThatIsAlreadyOnThePhoneDoesNothing() async throws {
        let harness = Harness()
        try harness.env.installFinished(alpha)
        await harness.manager.start("alpha")
        #expect(await harness.manager.state(of: "alpha") == .downloaded)
        #expect(harness.downloader.calls.isEmpty)
    }

    @Test func startingTwiceDownloadsOnce() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 20))
        await harness.manager.start("alpha")
        await harness.manager.start("alpha")
        #expect(await harness.waitForProgress("alpha", 30))
        await harness.manager.start("alpha")
        await harness.manager.cancel("alpha")
        #expect(harness.downloader.calledFiles == ["config.json", "model.safetensors"])
    }

    @Test func unknownModelsAreIgnored() async throws {
        let harness = Harness()
        await harness.manager.start("nope")
        await harness.manager.pause("nope")
        await harness.manager.cancel("nope")
        try await harness.manager.delete("nope")
        #expect(harness.downloader.calls.isEmpty)
        #expect(await harness.manager.allStates() == ["alpha": .notDownloaded, "beta": .notDownloaded])
    }

    // MARK: Pause and resume

    @Test func pauseKeepsWhatArrivedAndResumeContinuesTheFileInFlight() async throws {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 40))
        await harness.manager.start("alpha")
        #expect(await harness.waitForProgress("alpha", 50))
        await harness.manager.pause("alpha")
        #expect(await harness.manager.state(of: "alpha") == .paused(progress(50, of: 110)))
        let record = try #require(harness.env.storage.resumeRecord(for: alpha))
        #expect(record.file == "model.safetensors")
        #expect(record.data == MockModelDownloader.resumeData(for: "model.safetensors"))
        #expect(record.receivedBytes == 40)

        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
        // config.json is not fetched again, and the second try carries the resume data.
        #expect(harness.downloader.calledFiles == ["config.json", "model.safetensors", "model.safetensors"])
        #expect(harness.downloader.calls.last?.resumeData == MockModelDownloader.resumeData(for: "model.safetensors"))
        #expect(harness.env.storage.resumeRecord(for: alpha) == nil)
        #expect(harness.env.storage.isDownloaded(alpha))
    }

    @Test func aPausedDownloadSurvivesARelaunch() async throws {
        let first = Harness()
        first.downloader.script(alpha, "model.safetensors", .hang(bytes: 40))
        await first.manager.start("alpha")
        #expect(await first.waitForProgress("alpha", 50))
        await first.manager.pause("alpha")

        // A new launch: a new manager over the same folder.
        let second = Harness(env: first.env)
        await second.manager.reload()
        #expect(await second.manager.state(of: "alpha") == .paused(progress(50, of: 110)))
        await second.manager.start("alpha")
        #expect(await second.waitForDownloaded("alpha"))
        #expect(second.downloader.calledFiles == ["model.safetensors"])
        #expect(second.downloader.calls.first?.resumeData == MockModelDownloader.resumeData(for: "model.safetensors"))
    }

    @Test func pausingAQueuedModelTakesItOutOfTheQueue() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 5))
        await harness.manager.start("alpha")
        await harness.manager.start("beta")
        #expect(await harness.manager.state(of: "beta") == .queued)
        await harness.manager.pause("beta")
        #expect(await harness.manager.state(of: "beta") == .paused(progress(0, of: 60)))
        await harness.manager.cancel("alpha")
        try? await Task.sleep(for: .milliseconds(40))
        #expect(harness.downloader.calls(for: beta).isEmpty)
        #expect(await harness.manager.state(of: "beta") == .paused(progress(0, of: 60)))
    }

    // MARK: Cancel and delete

    @Test func cancelThrowsAwayWhatArrived() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 40))
        await harness.manager.start("alpha")
        #expect(await harness.waitForProgress("alpha", 50))
        await harness.manager.cancel("alpha")
        #expect(await harness.manager.state(of: "alpha") == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: harness.env.storage.partialFolder(for: alpha).path))
        #expect(harness.env.storage.resumeRecord(for: alpha) == nil)
    }

    @Test func cancelLeavesAFinishedModelAlone() async throws {
        let harness = Harness()
        try harness.env.installFinished(alpha)
        await harness.manager.reload()
        await harness.manager.cancel("alpha")
        #expect(await harness.manager.state(of: "alpha") == .downloaded)
        #expect(harness.env.storage.isDownloaded(alpha))
    }

    @Test func cancelOfAQueuedModelLeavesTheDownloadInFrontRunning() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 5))
        await harness.manager.start("alpha")
        await harness.manager.start("beta")
        await harness.manager.cancel("beta")
        #expect(await harness.manager.state(of: "beta") == .notDownloaded)
        #expect(await harness.waitForProgress("alpha", 15))
        await harness.manager.pause("alpha")
        try? await Task.sleep(for: .milliseconds(40))
        #expect(harness.downloader.calls(for: beta).isEmpty)
    }

    @Test func deleteRemovesAFinishedModel() async throws {
        let harness = Harness()
        try harness.env.installFinished(alpha)
        await harness.manager.reload()
        #expect(await harness.manager.state(of: "alpha") == .downloaded)
        try await harness.manager.delete("alpha")
        #expect(await harness.manager.state(of: "alpha") == .notDownloaded)
        #expect(!FileManager.default.fileExists(atPath: harness.env.storage.folder(for: alpha).path))
        #expect(harness.env.storage.usedBytes() == 0)
    }

    @Test func deleteStopsARunningDownloadAndRemovesItsFiles() async throws {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 40))
        await harness.manager.start("alpha")
        #expect(await harness.waitForProgress("alpha", 50))
        try await harness.manager.delete("alpha")
        #expect(await harness.manager.state(of: "alpha") == .notDownloaded)
        #expect(harness.env.storage.usedBytes() == 0)
    }

    // MARK: Free space

    @Test func notEnoughSpaceFailsBeforeAnyByteMoves() async {
        let harness = Harness(freeBytes: 50, reserve: 100)
        await harness.manager.start("alpha")
        // 110 bytes of model plus the 100 byte reserve.
        #expect(
            await harness.manager.state(of: "alpha")
                == .failed(.notEnoughSpace(needed: 210, available: 50), progress(0, of: 110)))
        #expect(harness.downloader.calls.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: harness.env.storage.partialFolder(for: alpha).path))
    }

    @Test func theReserveCountsTowardsTheSpaceCheck() async {
        let harness = Harness(freeBytes: 209, reserve: 100)
        await harness.manager.start("alpha")
        #expect(
            await harness.manager.state(of: "alpha")
                == .failed(.notEnoughSpace(needed: 210, available: 209), progress(0, of: 110)))
        let exact = Harness(freeBytes: 210, reserve: 100)
        await exact.manager.start("alpha")
        #expect(await exact.waitForDownloaded("alpha"))
    }

    @Test func filesAlreadyOnThePhoneDoNotCountTowardsTheSpaceCheck() async throws {
        // 100 bytes left to fetch plus the 100 byte reserve fit in 205; the whole model would not.
        let harness = Harness(freeBytes: 205, reserve: 100)
        try harness.env.storage.preparePartialFolder(for: alpha)
        let file = alpha.files[0]
        try harness.env.storage.store(try harness.env.makeTemporaryFile(bytes: file.bytes), as: file, of: alpha)
        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
        #expect(harness.downloader.calledFiles == ["model.safetensors"])
    }

    @Test func aFailedSpaceCheckCanBeRetriedOnceThereIsRoom() async {
        let phone = DiskBox(50)
        let env = TestEnvironment()
        let downloader = MockModelDownloader(
            models: TestModels.catalog.models, directory: env.root.appendingPathComponent("downloads"))
        let manager = OnDeviceModelManager(
            catalog: TestModels.catalog, storage: env.storage, downloader: downloader,
            diskSpace: phone, reserveBytes: 100, progressStep: 1)
        await manager.start("alpha")
        let first = await manager.state(of: "alpha")
        #expect(first == .failed(.notEnoughSpace(needed: 210, available: 50), progress(0, of: 110)))
        phone.bytes = 10_000
        await manager.start("alpha")
        #expect(await waitUntil { await manager.state(of: "alpha") == .downloaded })
    }

    @Test func anUnknownAmountOfFreeSpaceDoesNotBlockTheDownload() async {
        let harness = Harness(freeBytes: nil)
        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
    }

    // MARK: Failures

    @Test func aServerErrorStopsTheDownloadAndRetryFinishesIt() async {
        let harness = Harness()
        harness.downloader.script(beta, "model.safetensors", .failStatus(503))
        await harness.manager.start("beta")
        #expect(await harness.waitForFailure("beta"))
        #expect(await harness.manager.state(of: "beta") == .failed(.server(status: 503), progress(10, of: 60)))
        await harness.manager.start("beta")
        #expect(await harness.waitForDownloaded("beta"))
        // The finished config.json is not fetched again.
        #expect(harness.downloader.calledFiles == ["config.json", "model.safetensors", "model.safetensors"])
    }

    @Test func aDroppedConnectionKeepsResumeDataForResumeInterrupted() async {
        let harness = Harness()
        let data = Data("partial".utf8)
        harness.downloader.script(
            alpha, "model.safetensors", .failNetwork("The connection was lost.", resumeData: data))
        await harness.manager.start("alpha")
        #expect(await harness.waitForFailure("alpha"))
        #expect(
            await harness.manager.state(of: "alpha")
                == .failed(.network("The connection was lost."), progress(10, of: 110)))
        #expect(harness.env.storage.resumeRecord(for: alpha)?.data == data)

        await harness.manager.resumeInterrupted()
        #expect(await harness.waitForDownloaded("alpha"))
        #expect(harness.downloader.calls.last?.resumeData == data)
    }

    @Test func resumeInterruptedLeavesOtherFailuresAlone() async {
        let harness = Harness()
        harness.downloader.script(alpha, "config.json", .failStatus(404))
        await harness.manager.start("alpha")
        #expect(await harness.waitForFailure("alpha"))
        await harness.manager.resumeInterrupted()
        try? await Task.sleep(for: .milliseconds(40))
        #expect(harness.downloader.calls.count == 1)
        #expect(await harness.manager.state(of: "alpha") == .failed(.server(status: 404), progress(0, of: 110)))
    }

    @Test func resumeDataTheSystemRefusesIsDroppedAndTheFileStartsOver() async throws {
        let harness = Harness()
        try harness.env.storage.preparePartialFolder(for: alpha)
        let stale = OnDeviceModelResumeRecord(file: "config.json", data: Data("stale".utf8), receivedBytes: 3)
        harness.env.storage.saveResumeRecord(stale, for: alpha)
        harness.downloader.script(
            alpha, "config.json", .failNetwork("The resume data is no longer valid.", resumeData: nil))
        await harness.manager.reload()
        #expect(await harness.manager.state(of: "alpha") == .paused(progress(3, of: 110)))
        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
        let configCalls: [Data?] = harness.downloader.calls.filter { $0.file == "config.json" }.map(\.resumeData)
        #expect(configCalls == [Data("stale".utf8), nil])
    }

    @Test func aFileOfTheWrongSizeIsDiscardedAndMarkedDamaged() async {
        let harness = Harness()
        harness.downloader.script(alpha, "config.json", .wrongSize(11))
        await harness.manager.start("alpha")
        #expect(await harness.waitForFailure("alpha"))
        #expect(
            await harness.manager.state(of: "alpha") == .failed(.damaged(file: "config.json"), progress(0, of: 110)))
        #expect(!harness.env.storage.hasPartialFile(alpha.files[0], of: alpha))
        await harness.manager.start("alpha")
        #expect(await harness.waitForDownloaded("alpha"))
    }

    @Test func aFileSystemErrorIsReportedAsStorageTrouble() async {
        let harness = Harness()
        harness.downloader.script(alpha, "config.json", .failFileSystem("No room to move the file."))
        await harness.manager.start("alpha")
        #expect(await harness.waitForFailure("alpha"))
        #expect(
            await harness.manager.state(of: "alpha")
                == .failed(.storage("No room to move the file."), progress(0, of: 110)))
    }

    // MARK: Queue

    @Test func downloadsRunOneAtATimeInTheOrderTheyWereStarted() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 5))
        await harness.manager.start("alpha")
        await harness.manager.start("beta")
        #expect(await harness.manager.state(of: "beta") == .queued)
        #expect(await harness.waitForProgress("alpha", 15))
        #expect(harness.downloader.calls(for: beta).isEmpty)

        await harness.manager.pause("alpha")
        #expect(await harness.waitForDownloaded("beta"))
        #expect(await harness.manager.state(of: "alpha") == .paused(progress(15, of: 110)))
        #expect(harness.downloader.calls(for: beta).map(\.file) == ["config.json", "model.safetensors"])
    }

    // MARK: Reading the disk

    @Test func reloadFindsFinishedAndPartialDownloads() async throws {
        let harness = Harness()
        try harness.env.installFinished(alpha)
        try harness.env.storage.preparePartialFolder(for: beta)
        let file = beta.files[0]
        try harness.env.storage.store(try harness.env.makeTemporaryFile(bytes: file.bytes), as: file, of: beta)
        await harness.manager.reload()
        #expect(await harness.manager.allStates() == ["alpha": .downloaded, "beta": .paused(progress(10, of: 60))])
    }

    @Test func reloadRemovesFoldersTheCatalogNoLongerLists() async throws {
        let harness = Harness()
        let ghost = harness.env.storage.root.appendingPathComponent("retired-model", isDirectory: true)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        try Data(count: 8).write(to: ghost.appendingPathComponent("model.safetensors"))
        await harness.manager.reload()
        #expect(!FileManager.default.fileExists(atPath: ghost.path))
    }

    @Test func reloadDoesNotDisturbADownloadInProgress() async {
        let harness = Harness()
        harness.downloader.script(alpha, "model.safetensors", .hang(bytes: 40))
        await harness.manager.start("alpha")
        #expect(await harness.waitForProgress("alpha", 50))
        await harness.manager.reload()
        let state = await harness.manager.state(of: "alpha")
        guard case .downloading(let running) = state else {
            Issue.record("the download should still run, but the state is \(state)")
            return
        }
        #expect(running.receivedBytes >= 50)
        await harness.manager.cancel("alpha")
    }
}

/// A disk with a number a test can change between calls.
private final class DiskBox: DiskSpaceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64

    init(_ bytes: Int64) {
        stored = bytes
    }

    var bytes: Int64 {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }

    func availableBytes(at url: URL) -> Int64? { bytes }
}
