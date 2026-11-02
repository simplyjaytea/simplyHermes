import Foundation
import Testing

@testable import HermesKit

struct OnDeviceModelsStorageTests {
    private let alpha = TestModels.alpha
    private let beta = TestModels.beta

    @Test func defaultRootIsUnderApplicationSupport() {
        let path = OnDeviceModelStorage.defaultRoot().path
        #expect(path.hasSuffix("simplyHermes/OnDeviceModels"))
    }

    @Test func foldersAreNamedByModelID() {
        let env = TestEnvironment()
        #expect(env.storage.folder(for: alpha).lastPathComponent == "alpha")
        #expect(env.storage.partialFolder(for: alpha).lastPathComponent == "alpha.partial")
        #expect(env.storage.folder(for: alpha).deletingLastPathComponent() == env.storage.root)
    }

    @Test func storeChecksTheSizeAndMovesTheFile() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        let file = alpha.files[0]
        let temporary = try env.makeTemporaryFile(bytes: file.bytes)
        try env.storage.store(temporary, as: file, of: alpha)
        #expect(env.storage.hasPartialFile(file, of: alpha))
        #expect(env.storage.partialBytes(for: alpha) == file.bytes)
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
    }

    @Test func storeRejectsAWrongSizeAndDeletesTheFile() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        let file = alpha.files[0]
        let temporary = try env.makeTemporaryFile(bytes: file.bytes + 1)
        #expect(
            throws: OnDeviceModelStorageError.sizeMismatch(path: file.path, expected: 10, actual: 11)
        ) {
            try env.storage.store(temporary, as: file, of: alpha)
        }
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(!env.storage.hasPartialFile(file, of: alpha))
    }

    @Test func storeRejectsADigestMismatchAndDeletesTheFile() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        let file = alpha.files[0]
        // The right size with other content: a size check alone would let this through to MLX.
        let temporary = try env.makeTemporaryFile(bytes: file.bytes)
        try Data(repeating: 0xFF, count: Int(file.bytes)).write(to: temporary)
        #expect(throws: OnDeviceModelStorageError.digestMismatch(path: file.path)) {
            try env.storage.store(temporary, as: file, of: alpha)
        }
        #expect(!FileManager.default.fileExists(atPath: temporary.path))
        #expect(!env.storage.hasPartialFile(file, of: alpha))
    }

    @Test func completeChecksEveryDigestAgain() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        for file in alpha.files {
            try env.storage.store(env.makeTemporaryFile(bytes: file.bytes), as: file, of: alpha)
        }
        // Changed on disk after it was stored, with the same size.
        let weights = env.storage.partialFolder(for: alpha).appendingPathComponent("model.safetensors")
        try Data(repeating: 0xFF, count: 100).write(to: weights)
        #expect(throws: OnDeviceModelStorageError.digestMismatch(path: "model.safetensors")) {
            try env.storage.complete(alpha)
        }
        #expect(!env.storage.isDownloaded(alpha))
        #expect(!env.storage.hasPartialFile(alpha.files[1], of: alpha))
        #expect(env.storage.hasPartialFile(alpha.files[0], of: alpha))
    }

    @Test func storeRejectsPathsThatLeaveTheFolder() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        let evil = OnDeviceModelFile.zeros("../escape.json", 4)
        let temporary = try env.makeTemporaryFile(bytes: 4)
        #expect(throws: OnDeviceModelStorageError.unsafePath("../escape.json")) {
            try env.storage.store(temporary, as: evil, of: alpha)
        }
        #expect(!env.storage.hasPartialFile(evil, of: alpha))
    }

    @Test func completeTurnsThePartialFolderIntoTheFinishedOne() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        #expect(env.storage.isDownloaded(alpha))
        #expect(!FileManager.default.fileExists(atPath: env.storage.partialFolder(for: alpha).path))
        #expect(env.storage.usedBytes(for: alpha) > alpha.totalBytes)  // the files and the manifest
        #expect(!env.storage.isDownloaded(beta))
    }

    @Test func completeFailsWhenAFileIsMissing() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        let file = alpha.files[0]
        try env.storage.store(try env.makeTemporaryFile(bytes: file.bytes), as: file, of: alpha)
        #expect(throws: OnDeviceModelStorageError.incomplete(path: "model.safetensors")) {
            try env.storage.complete(alpha)
        }
        #expect(!env.storage.isDownloaded(alpha))
    }

    @Test func aFinishedModelWithAChangedFileIsNotDownloaded() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        let weights = env.storage.folder(for: alpha).appendingPathComponent("model.safetensors")
        try Data(count: 5).write(to: weights)
        #expect(!env.storage.isDownloaded(alpha))
    }

    @Test func aFinishedModelWithoutDigestsIsNotDownloaded() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        // The manifest a version before digests wrote: same id, revision and size, no digests.
        let legacy = #"{"id":"alpha","revision":"\#(alpha.revision)","bytes":110}"#
        try Data(legacy.utf8).write(to: env.storage.folder(for: alpha).appendingPathComponent(".complete.json"))
        #expect(!env.storage.isDownloaded(alpha))
    }

    @Test func aFinishedModelWithAChangedDigestIsNotDownloaded() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        let config = alpha.files[0]
        let repinned = OnDeviceModel(
            id: alpha.id, displayName: alpha.displayName, summary: alpha.summary, repository: alpha.repository,
            revision: alpha.revision,
            files: [
                OnDeviceModelFile(config.path, config.bytes, sha256: OnDeviceModelDigest.sha256(of: Data("x".utf8))),
                alpha.files[1],
            ],
            license: alpha.license)
        #expect(env.storage.isDownloaded(alpha))
        #expect(!env.storage.isDownloaded(repinned))
    }

    @Test func aFinishedModelFromAnotherRevisionIsNotDownloaded() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        let newer = OnDeviceModel(
            id: alpha.id, displayName: alpha.displayName, summary: alpha.summary, repository: alpha.repository,
            revision: String(repeating: "c", count: 40), files: alpha.files, license: alpha.license)
        #expect(env.storage.isDownloaded(alpha))
        #expect(!env.storage.isDownloaded(newer))
    }

    @Test func rootAndModelFoldersAreExcludedFromBackup() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        let excluded = env.excludedFromBackup.map(\.lastPathComponent)
        #expect(excluded.contains("models"))
        #expect(excluded.contains("alpha.partial"))
        #expect(excluded.contains("alpha"))
    }

    @Test func removeDeletesTheFinishedModelAndAnyPartialDownload() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        try env.storage.preparePartialFolder(for: alpha)
        try env.storage.remove(alpha)
        #expect(!FileManager.default.fileExists(atPath: env.storage.folder(for: alpha).path))
        #expect(!FileManager.default.fileExists(atPath: env.storage.partialFolder(for: alpha).path))
        try env.storage.remove(alpha)  // nothing left: still fine
    }

    @Test func usedBytesCountsEveryFileUnderTheRoot() throws {
        let env = TestEnvironment()
        #expect(env.storage.usedBytes() == 0)
        try env.installFinished(alpha)
        try env.installFinished(beta)
        let used = env.storage.usedBytes()
        #expect(used >= alpha.totalBytes + beta.totalBytes)
        #expect(used < alpha.totalBytes + beta.totalBytes + 1000)  // plus two small manifests
    }

    @Test func removeOrphansKeepsWhatTheCatalogAccountsFor() throws {
        let env = TestEnvironment()
        try env.installFinished(alpha)
        try env.storage.preparePartialFolder(for: beta)
        env.storage.saveChoice(.downloaded("alpha"))
        let ghost = env.storage.root.appendingPathComponent("ghost", isDirectory: true)
        try FileManager.default.createDirectory(at: ghost, withIntermediateDirectories: true)
        try Data(count: 3).write(to: env.storage.root.appendingPathComponent("stray.bin"))
        // A finished folder with no manifest cannot be used, so it goes too.
        let broken = env.storage.folder(for: beta)
        try FileManager.default.createDirectory(at: broken, withIntermediateDirectories: true)

        env.storage.removeOrphans(keeping: TestModels.catalog)

        let names = Set((try FileManager.default.contentsOfDirectory(atPath: env.storage.root.path)))
        #expect(names == ["alpha", "beta.partial", "selection.json"])
    }

    @Test func resumeRecordRoundTripsAndIsClearedWhenAModelFinishes() throws {
        let env = TestEnvironment()
        try env.storage.preparePartialFolder(for: alpha)
        #expect(env.storage.resumeRecord(for: alpha) == nil)
        let record = OnDeviceModelResumeRecord(file: "model.safetensors", data: Data("abc".utf8), receivedBytes: 42)
        env.storage.saveResumeRecord(record, for: alpha)
        #expect(env.storage.resumeRecord(for: alpha) == record)
        #expect(env.storage.hasPartialDownload(alpha))
        env.storage.clearResumeRecord(for: alpha)
        #expect(env.storage.resumeRecord(for: alpha) == nil)
        #expect(!env.storage.hasPartialDownload(alpha))
    }

    @Test func choiceRoundTrips() {
        let env = TestEnvironment()
        #expect(env.storage.loadChoice() == nil)
        env.storage.saveChoice(.downloaded("beta"))
        #expect(env.storage.loadChoice() == .downloaded("beta"))
        env.storage.saveChoice(.apple)
        #expect(env.storage.loadChoice() == .apple)
    }

    @Test func anUnreadableChoiceFileCountsAsNoChoice() throws {
        let env = TestEnvironment()
        try env.storage.prepareRoot()
        try Data("not json".utf8).write(to: env.storage.root.appendingPathComponent("selection.json"))
        #expect(env.storage.loadChoice() == nil)
    }

    @Test func systemDiskSpaceAsksTheNearestExistingFolder() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)/deeper/still", isDirectory: true)
        let bytes = SystemDiskSpace().availableBytes(at: missing)
        #expect((bytes ?? 0) > 0)
    }
}
