import Foundation

/// Why a file could not be put in a model folder.
public enum OnDeviceModelStorageError: Error, Sendable, Equatable {
    /// The file on disk is not the size the catalog says. The file is deleted.
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    /// The file has the right size but not the catalog's SHA-256. The file is deleted.
    case digestMismatch(path: String)
    /// The catalog path would leave the model folder.
    case unsafePath(String)
    /// A file is missing when the model is finished.
    case incomplete(path: String)
    /// The file system refused.
    case fileSystem(String)
    /// A file of an earlier download could not be read to check it. Nothing was changed.
    case unreadable(path: String)
}

/// What the app remembers about a download that was stopped part way through a file.
public struct OnDeviceModelResumeRecord: Sendable, Equatable, Codable {
    /// The catalog path of the file that was in flight.
    public var file: String
    /// The URL loading system's resume data for that file.
    public var data: Data
    /// How many bytes of that file had arrived.
    public var receivedBytes: Int64

    public init(file: String, data: Data, receivedBytes: Int64) {
        self.file = file
        self.data = data
        self.receivedBytes = receivedBytes
    }
}

/// Where downloaded models live on disk, and what is in each folder.
///
/// Layout under `root` (the app uses Application Support/simplyHermes/OnDeviceModels):
/// - `<id>/` is a finished model. It exists only when every file is there with the right size and SHA-256.
/// - `<id>.partial/` is a download in progress. Finished files stay in it, so a restart skips them. `.verified.json`
///   lists the files whose SHA-256 was checked when they arrived. `.repair.json` lists the files an earlier download
///   failed to verify, which are fetched again.
/// - `selection.json` is the model the user picked.
///
/// The root and every model folder are excluded from iCloud and device backups: they can be downloaded again.
public struct OnDeviceModelStorage: Sendable {
    public let root: URL
    private let excludeFromBackup: @Sendable (URL) -> Void
    private let digest: @Sendable (URL) throws -> String

    private static let manifestName = ".complete.json"
    private static let resumeName = ".resume.json"
    private static let verifiedName = ".verified.json"
    private static let repairName = ".repair.json"
    private static let selectionName = "selection.json"
    private static let partialSuffix = ".partial"

    private struct Manifest: Codable {
        var id: String
        var revision: String
        var bytes: Int64
        /// The SHA-256 of each file, as checked. Missing in folders written before digests existed, and those are not
        /// trusted until they are checked (see ``OnDeviceModelStorage/checkEarlierDownload(_:)``).
        var digests: [String: String]?
    }

    /// `excludeFromBackup` marks a folder as not to be backed up. `digest` hashes a file; tests replace it to count
    /// the hashes or to fail a read.
    public init(
        root: URL,
        excludeFromBackup: @escaping @Sendable (URL) -> Void = OnDeviceModelStorage.exclude,
        digest: @escaping @Sendable (URL) throws -> String = { try OnDeviceModelDigest.sha256(of: $0) }
    ) {
        self.root = root
        self.excludeFromBackup = excludeFromBackup
        self.digest = digest
    }

    /// Application Support/simplyHermes/OnDeviceModels.
    public static func defaultRoot() -> URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("simplyHermes", isDirectory: true)
            .appendingPathComponent("OnDeviceModels", isDirectory: true)
    }

    /// Sets `isExcludedFromBackup` on `url`. A failure is ignored: the backup flag is a courtesy, not a requirement.
    @Sendable
    public static func exclude(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    // MARK: Paths

    /// The folder of a finished model.
    public func folder(for model: OnDeviceModel) -> URL {
        root.appendingPathComponent(model.id, isDirectory: true)
    }

    /// The folder of a download in progress.
    public func partialFolder(for model: OnDeviceModel) -> URL {
        root.appendingPathComponent(model.id + Self.partialSuffix, isDirectory: true)
    }

    // MARK: State on disk

    /// True when the manifest is there with the catalog's digests and every file has the catalog's size. Digests are
    /// checked when a file arrives or is checked, not on every call, because hashing gigabytes on each Settings open is
    /// too slow.
    public func isDownloaded(_ model: OnDeviceModel) -> Bool {
        let folder = folder(for: model)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest.id == model.id, manifest.revision == model.revision,
            manifest.digests == digests(of: model)
        else { return false }
        return model.files.allSatisfy { fileSize(at: folder.appendingPathComponent($0.path)) == $0.bytes }
    }

    /// True when a finished folder of `model` was written before digests existed. Its files have not been checked
    /// against the catalog yet, so it is not usable until ``checkEarlierDownload(_:)`` has checked it.
    public func hasEarlierDownload(_ model: OnDeviceModel) -> Bool {
        guard let data = try? Data(contentsOf: folder(for: model).appendingPathComponent(Self.manifestName)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data)
        else { return false }
        return manifest.id == model.id && manifest.revision == model.revision && manifest.digests == nil
    }

    /// The files an earlier download failed to verify, which are fetched again. Empty when there are none.
    public func repairingFiles(_ model: OnDeviceModel) -> [String] {
        let url = partialFolder(for: model).appendingPathComponent(Self.repairName)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
    }

    /// True while a model is being checked or repaired. Such a model is not usable, and it is not a reason to answer
    /// with another model either.
    public func isAwaitingCheck(_ model: OnDeviceModel) -> Bool {
        hasEarlierDownload(model) || !repairingFiles(model).isEmpty
    }

    /// True when `file` has finished downloading into the partial folder.
    public func hasPartialFile(_ file: OnDeviceModelFile, of model: OnDeviceModel) -> Bool {
        file.hasSafePath && fileSize(at: partialFolder(for: model).appendingPathComponent(file.path)) == file.bytes
    }

    /// Bytes in files that finished downloading and are waiting in the partial folder.
    public func partialBytes(for model: OnDeviceModel) -> Int64 {
        model.files.filter { hasPartialFile($0, of: model) }.reduce(0) { $0 + $1.bytes }
    }

    /// True when a partial folder with something worth resuming exists.
    public func hasPartialDownload(_ model: OnDeviceModel) -> Bool {
        partialBytes(for: model) > 0 || resumeRecord(for: model) != nil
    }

    // MARK: Writing

    /// Creates the root folder and keeps it out of backups.
    public func prepareRoot() throws {
        try createDirectory(root)
        excludeFromBackup(root)
    }

    /// Creates the folder a download writes into.
    public func preparePartialFolder(for model: OnDeviceModel) throws {
        try prepareRoot()
        let folder = partialFolder(for: model)
        try createDirectory(folder)
        excludeFromBackup(folder)
    }

    /// Moves a finished download into the partial folder as `file`, after checking its size and SHA-256. The file is
    /// hashed once, here, after its download has finished.
    public func store(_ temporary: URL, as file: OnDeviceModelFile, of model: OnDeviceModel) throws {
        let fileManager = FileManager.default
        guard file.hasSafePath else {
            try? fileManager.removeItem(at: temporary)
            throw OnDeviceModelStorageError.unsafePath(file.path)
        }
        let actual = fileSize(at: temporary) ?? -1
        guard actual == file.bytes else {
            try? fileManager.removeItem(at: temporary)
            throw OnDeviceModelStorageError.sizeMismatch(path: file.path, expected: file.bytes, actual: actual)
        }
        let digest: String
        do {
            digest = try verifiedDigest(of: temporary)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
        guard digest == file.sha256 else {
            try? fileManager.removeItem(at: temporary)
            throw OnDeviceModelStorageError.digestMismatch(path: file.path)
        }
        let destination = partialFolder(for: model).appendingPathComponent(file.path)
        do {
            try createDirectory(destination.deletingLastPathComponent())
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
        try recordVerified([file.path: file.sha256], for: model)
    }

    /// Turns the partial folder into the finished model folder. Throws when a file is missing, the wrong size or the
    /// wrong digest. A file that was verified when it arrived is not hashed again. A file that was not (one left by an
    /// earlier version) is hashed here, and a bad one is deleted so that only it is fetched again.
    public func complete(_ model: OnDeviceModel) throws {
        let fileManager = FileManager.default
        let partial = partialFolder(for: model)
        let verified = verifiedDigests(for: model)
        for file in model.files {
            guard hasPartialFile(file, of: model) else {
                throw OnDeviceModelStorageError.incomplete(path: file.path)
            }
            if verified[file.path] == file.sha256 { continue }
            let url = partial.appendingPathComponent(file.path)
            guard try verifiedDigest(of: url) == file.sha256 else {
                try? fileManager.removeItem(at: url)
                throw OnDeviceModelStorageError.digestMismatch(path: file.path)
            }
            try recordVerified([file.path: file.sha256], for: model)
        }
        let manifest = Manifest(
            id: model.id, revision: model.revision, bytes: model.totalBytes, digests: digests(of: model))
        do {
            try JSONEncoder().encode(manifest).write(to: partial.appendingPathComponent(Self.manifestName))
            for name in [Self.resumeName, Self.verifiedName, Self.repairName] {
                try? fileManager.removeItem(at: partial.appendingPathComponent(name))
            }
            let final = folder(for: model)
            try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: partial, to: final)
            excludeFromBackup(final)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    /// Checks the files of an earlier download, written before digests existed, against the catalog.
    ///
    /// When every file matches, the folder becomes a finished model in place, and nothing is downloaded. Otherwise the
    /// files that do not match are left out, the files that do match move into the partial folder, the names of the
    /// bad ones are recorded for a download to fetch, and the old folder is removed. Returns those names, which is
    /// empty when every file matched. A file that cannot be read throws and changes nothing.
    public func checkEarlierDownload(_ model: OnDeviceModel) throws -> [String] {
        let fileManager = FileManager.default
        let folder = folder(for: model)
        var bad: [String] = []
        var good: [OnDeviceModelFile] = []
        for file in model.files {
            let url = folder.appendingPathComponent(file.path)
            guard file.hasSafePath, fileSize(at: url) == file.bytes else {
                bad.append(file.path)
                continue
            }
            let actual: String
            do {
                actual = try digest(url)
            } catch {
                throw OnDeviceModelStorageError.unreadable(path: file.path)
            }
            if actual == file.sha256 {
                good.append(file)
            } else {
                bad.append(file.path)
            }
        }
        if bad.isEmpty {
            let manifest = Manifest(
                id: model.id, revision: model.revision, bytes: model.totalBytes, digests: digests(of: model))
            do {
                try JSONEncoder().encode(manifest).write(to: folder.appendingPathComponent(Self.manifestName))
            } catch {
                throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
            }
            return []
        }
        try preparePartialFolder(for: model)
        let partial = partialFolder(for: model)
        do {
            for file in good {
                let destination = partial.appendingPathComponent(file.path)
                try createDirectory(destination.deletingLastPathComponent())
                try? fileManager.removeItem(at: destination)
                try fileManager.moveItem(at: folder.appendingPathComponent(file.path), to: destination)
            }
            try JSONEncoder().encode(bad).write(to: partial.appendingPathComponent(Self.repairName))
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
        try recordVerified(
            Dictionary(good.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first }),
            for: model)
        try? fileManager.removeItem(at: folder)
        return bad
    }

    /// The bytes on disk that deleting the model would free: its finished folder and its partial folder. Nil when a
    /// file cannot be measured, so the caller can leave the number out.
    public func measuredBytes(for model: OnDeviceModel) -> Int64? {
        measuredBytes(for: model, sizeOf: { self.fileSize(at: $0) })
    }

    func measuredBytes(for model: OnDeviceModel, sizeOf: (URL) -> Int64?) -> Int64? {
        let fileManager = FileManager.default
        var total: Int64 = 0
        let folders = [folder(for: model), partialFolder(for: model)]
        for folder in folders where fileManager.fileExists(atPath: folder.path) {
            guard let walker = fileManager.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])
            else { return nil }
            for case let item as URL in walker {
                guard (try? item.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                guard let bytes = sizeOf(item) else { return nil }
                total += bytes
            }
        }
        return total
    }

    /// Deletes the finished model and any partial download of it.
    public func remove(_ model: OnDeviceModel) throws {
        do {
            try removeIfPresent(folder(for: model))
            try removeIfPresent(partialFolder(for: model))
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    /// Deletes only the partial download.
    public func removePartial(_ model: OnDeviceModel) {
        try? removeIfPresent(partialFolder(for: model))
    }

    /// Deletes everything in the root that the catalog does not account for: folders of models that left the catalog,
    /// finished folders that no longer match their catalog entry, and stray files. Keeps the saved selection, and an
    /// earlier download, which stays until it has been checked.
    public func removeOrphans(keeping catalog: OnDeviceModelCatalog) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
        let valid = Set(catalog.models.filter { isDownloaded($0) || hasEarlierDownload($0) }.map(\.id))
        let partials = Set(catalog.models.map { $0.id + Self.partialSuffix })
        for name in names where name != Self.selectionName && !valid.contains(name) && !partials.contains(name) {
            try? fileManager.removeItem(at: root.appendingPathComponent(name))
        }
    }

    // MARK: Size on disk

    /// Bytes used by everything under the root.
    public func usedBytes() -> Int64 {
        sizeOfFiles(under: root)
    }

    /// Bytes used by one model, finished or partial.
    public func usedBytes(for model: OnDeviceModel) -> Int64 {
        sizeOfFiles(under: folder(for: model)) + sizeOfFiles(under: partialFolder(for: model))
    }

    // MARK: Resume data

    /// Remembers where the file in flight stopped, so the next start continues it.
    public func saveResumeRecord(_ record: OnDeviceModelResumeRecord, for model: OnDeviceModel) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: partialFolder(for: model).appendingPathComponent(Self.resumeName))
    }

    public func resumeRecord(for model: OnDeviceModel) -> OnDeviceModelResumeRecord? {
        let url = partialFolder(for: model).appendingPathComponent(Self.resumeName)
        return (try? Data(contentsOf: url)).flatMap {
            try? JSONDecoder().decode(OnDeviceModelResumeRecord.self, from: $0)
        }
    }

    public func clearResumeRecord(for model: OnDeviceModel) {
        try? removeIfPresent(partialFolder(for: model).appendingPathComponent(Self.resumeName))
    }

    // MARK: Selection

    /// The saved choice, or nil when nothing was saved or the file is unreadable.
    public func loadChoice() -> OnDeviceModelChoice? {
        (try? Data(contentsOf: root.appendingPathComponent(Self.selectionName)))
            .flatMap { try? JSONDecoder().decode(OnDeviceModelChoice.self, from: $0) }
    }

    /// True when a choice file exists but cannot be read or decoded. A fresh install has no file, so this is false there.
    public func hasUnreadableChoice() -> Bool {
        let url = root.appendingPathComponent(Self.selectionName)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        return loadChoice() == nil
    }

    public func saveChoice(_ choice: OnDeviceModelChoice) {
        do {
            try prepareRoot()
            try JSONEncoder().encode(choice).write(to: root.appendingPathComponent(Self.selectionName))
        } catch {
            // The choice is a convenience: the next launch reads the last choice that was saved.
        }
    }

    // MARK: Helpers

    private func digests(of model: OnDeviceModel) -> [String: String] {
        Dictionary(model.files.map { ($0.path, $0.sha256) }, uniquingKeysWith: { first, _ in first })
    }

    /// The SHA-256 recorded for each file that was verified when it arrived, or checked, in the partial folder.
    private func verifiedDigests(for model: OnDeviceModel) -> [String: String] {
        let url = partialFolder(for: model).appendingPathComponent(Self.verifiedName)
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
            ?? [:]
    }

    /// Adds `entries` to the verified record of the partial folder.
    private func recordVerified(_ entries: [String: String], for model: OnDeviceModel) throws {
        var all = verifiedDigests(for: model)
        all.merge(entries) { _, new in new }
        do {
            try JSONEncoder().encode(all).write(to: partialFolder(for: model).appendingPathComponent(Self.verifiedName))
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    /// The SHA-256 of `url`. A file that cannot be read is a file-system failure, not a digest mismatch.
    private func verifiedDigest(of url: URL) throws -> String {
        do {
            return try digest(url)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    private func createDirectory(_ url: URL) throws {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    private func fileSize(at url: URL) -> Int64? {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        return size?.int64Value
    }

    private func sizeOfFiles(under url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in walker {
            let values = try? item.resourceValues(forKeys: Set(keys))
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }
}

/// How much room the phone has left.
public protocol DiskSpaceProviding: Sendable {
    /// Bytes available for new files on the volume that holds `url`, or nil when that cannot be read.
    func availableBytes(at url: URL) -> Int64?
}

/// Reads the real volume. On Apple platforms it uses the "important usage" figure, which counts space the system
/// can free by purging caches.
public struct SystemDiskSpace: DiskSpaceProviding {
    public init() {}

    public func availableBytes(at url: URL) -> Int64? {
        // The model folder does not exist before the first download: ask the nearest folder that does.
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            if parent == probe { break }
            probe = parent
        }
        #if canImport(Darwin)
            let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let bytes = values?.volumeAvailableCapacityForImportantUsage { return bytes }
        #endif
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: probe.path)
        return (attributes?[.systemFreeSize] as? NSNumber)?.int64Value
    }
}
