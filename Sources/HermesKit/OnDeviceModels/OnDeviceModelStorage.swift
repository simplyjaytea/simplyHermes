import Foundation

/// Why a file could not be put in a model folder.
public enum OnDeviceModelStorageError: Error, Sendable, Equatable {
    /// The file on disk is not the size the catalog says. The file is deleted.
    case sizeMismatch(path: String, expected: Int64, actual: Int64)
    /// The catalog path would leave the model folder.
    case unsafePath(String)
    /// A file is missing when the model is finished.
    case incomplete(path: String)
    /// The file system refused.
    case fileSystem(String)
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
/// - `<id>/` is a finished model. It exists only when every file is there with the right size.
/// - `<id>.partial/` is a download in progress. Finished files stay in it, so a restart skips them.
/// - `selection.json` is the model the user picked.
///
/// The root and every model folder are excluded from iCloud and device backups: they can be downloaded again.
public struct OnDeviceModelStorage: Sendable {
    public let root: URL
    private let excludeFromBackup: @Sendable (URL) -> Void

    private static let manifestName = ".complete.json"
    private static let resumeName = ".resume.json"
    private static let selectionName = "selection.json"
    private static let partialSuffix = ".partial"

    private struct Manifest: Codable {
        var id: String
        var revision: String
        var bytes: Int64
    }

    /// `excludeFromBackup` marks a folder as not to be backed up. Tests replace it to see which folders get it.
    public init(root: URL, excludeFromBackup: @escaping @Sendable (URL) -> Void = OnDeviceModelStorage.exclude) {
        self.root = root
        self.excludeFromBackup = excludeFromBackup
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

    /// True when the manifest is there and every file has the catalog's size.
    public func isDownloaded(_ model: OnDeviceModel) -> Bool {
        let folder = folder(for: model)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(Self.manifestName)),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest.id == model.id, manifest.revision == model.revision
        else { return false }
        return model.files.allSatisfy { fileSize(at: folder.appendingPathComponent($0.path)) == $0.bytes }
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

    /// Moves a finished download into the partial folder as `file`, after checking its size.
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
        let destination = partialFolder(for: model).appendingPathComponent(file.path)
        do {
            try createDirectory(destination.deletingLastPathComponent())
            try? fileManager.removeItem(at: destination)
            try fileManager.moveItem(at: temporary, to: destination)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
    }

    /// Turns the partial folder into the finished model folder. Throws when a file is missing or the wrong size.
    public func complete(_ model: OnDeviceModel) throws {
        let fileManager = FileManager.default
        for file in model.files where !hasPartialFile(file, of: model) {
            throw OnDeviceModelStorageError.incomplete(path: file.path)
        }
        let partial = partialFolder(for: model)
        let manifest = Manifest(id: model.id, revision: model.revision, bytes: model.totalBytes)
        do {
            try JSONEncoder().encode(manifest).write(to: partial.appendingPathComponent(Self.manifestName))
            try? fileManager.removeItem(at: partial.appendingPathComponent(Self.resumeName))
            let final = folder(for: model)
            try? fileManager.removeItem(at: final)
            try fileManager.moveItem(at: partial, to: final)
            excludeFromBackup(final)
        } catch {
            throw OnDeviceModelStorageError.fileSystem(error.localizedDescription)
        }
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
    /// finished folders that no longer match their catalog entry, and stray files. Keeps the saved selection.
    public func removeOrphans(keeping catalog: OnDeviceModelCatalog) {
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: root.path) else { return }
        let valid = Set(catalog.models.filter(isDownloaded).map(\.id))
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

    public func saveChoice(_ choice: OnDeviceModelChoice) {
        do {
            try prepareRoot()
            try JSONEncoder().encode(choice).write(to: root.appendingPathComponent(Self.selectionName))
        } catch {
            // The choice is a convenience: the next launch starts on the Apple model.
        }
    }

    // MARK: Helpers

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
