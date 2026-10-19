import Foundation

/// How much of a model has arrived.
public struct OnDeviceModelProgress: Sendable, Equatable {
    public var receivedBytes: Int64
    public var totalBytes: Int64

    public init(receivedBytes: Int64, totalBytes: Int64) {
        self.receivedBytes = receivedBytes
        self.totalBytes = totalBytes
    }

    /// 0 to 1.
    public var fraction: Double {
        totalBytes > 0 ? min(1, max(0, Double(receivedBytes) / Double(totalBytes))) : 0
    }
}

/// Why a download stopped.
public enum OnDeviceModelFailure: Sendable, Equatable {
    /// The phone does not have room. The download did not start.
    case notEnoughSpace(needed: Int64, available: Int64)
    /// The connection failed or dropped. Retry continues the file where it stopped when it can.
    case network(String)
    /// Hugging Face answered with this HTTP status.
    case server(status: Int)
    /// A finished file was the wrong size and was thrown away.
    case damaged(file: String)
    /// The phone's file system refused a write.
    case storage(String)
}

/// Where one model is in its life on this phone.
public enum OnDeviceModelState: Sendable, Equatable {
    case notDownloaded
    /// Waiting for the download in front of it.
    case queued
    case downloading(OnDeviceModelProgress)
    /// Stopped by the user, or left over from an earlier launch. Resume continues it.
    case paused(OnDeviceModelProgress)
    case failed(OnDeviceModelFailure, OnDeviceModelProgress)
    /// All files are on the phone and checked.
    case downloaded
}

/// A state change, as sent to anyone watching the manager.
public struct OnDeviceModelUpdate: Sendable, Equatable {
    public let id: String
    public let state: OnDeviceModelState

    public init(id: String, state: OnDeviceModelState) {
        self.id = id
        self.state = state
    }
}

/// Downloads the models in the catalog, one at a time, and keeps track of what is on the phone (plan WP-65c).
///
/// A download goes file by file into `<id>.partial/`. Finished files stay there, so pause, a failure and a restart
/// lose at most the file in flight, and resume data continues that file. When every file has the right size the folder
/// is renamed to `<id>/`. Before anything starts the manager checks that the phone has room for what is left plus a
/// reserve.
public actor OnDeviceModelManager {
    /// Space left free on the phone after a download (512 MiB).
    public static let defaultReserveBytes: Int64 = 512 * 1_048_576

    private enum Stop {
        case pause
        case cancel
    }

    private struct Active {
        let id: String
        let token: UUID
        var task: Task<Void, Never>?
        var stop: Stop?
        var fileIndex = 0
        /// Bytes of the files finished before the current one.
        var baseBytes: Int64 = 0
        var receivedBytes: Int64 = 0
        var publishedBytes: Int64 = 0
    }

    private let catalog: OnDeviceModelCatalog
    private let storage: OnDeviceModelStorage
    private let downloader: any ModelFileDownloader
    private let diskSpace: any DiskSpaceProviding
    private let reserveBytes: Int64
    private let progressStep: Int64

    private var states: [String: OnDeviceModelState] = [:]
    private var queue: [String] = []
    private var active: Active?
    private var subscribers: [UUID: AsyncStream<OnDeviceModelUpdate>.Continuation] = [:]

    /// `progressStep` is how many bytes must arrive before the next progress update goes out.
    public init(
        catalog: OnDeviceModelCatalog = .standard,
        storage: OnDeviceModelStorage,
        downloader: any ModelFileDownloader,
        diskSpace: any DiskSpaceProviding = SystemDiskSpace(),
        reserveBytes: Int64 = OnDeviceModelManager.defaultReserveBytes,
        progressStep: Int64 = 512 * 1024
    ) {
        self.catalog = catalog
        self.storage = storage
        self.downloader = downloader
        self.diskSpace = diskSpace
        self.reserveBytes = reserveBytes
        self.progressStep = max(1, progressStep)
    }

    // MARK: Reading

    /// The state of one model. A model the manager has not looked at yet counts as not downloaded.
    public func state(of id: String) -> OnDeviceModelState {
        states[id] ?? .notDownloaded
    }

    /// The state of every model in the catalog.
    public func allStates() -> [String: OnDeviceModelState] {
        Dictionary(uniqueKeysWithValues: catalog.models.map { ($0.id, states[$0.id] ?? .notDownloaded) })
    }

    /// State changes from now on, starting with the current state of every model.
    public func updates() -> AsyncStream<OnDeviceModelUpdate> {
        let (stream, continuation) = AsyncStream.makeStream(of: OnDeviceModelUpdate.self)
        let key = UUID()
        subscribers[key] = continuation
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeSubscriber(key) }
        }
        for model in catalog.models {
            continuation.yield(OnDeviceModelUpdate(id: model.id, state: states[model.id] ?? .notDownloaded))
        }
        return stream
    }

    /// Reads the disk: which models are finished, which have a partial download. Removes folders the catalog no
    /// longer lists. Call once at launch and when Settings opens.
    public func reload() {
        storage.removeOrphans(keeping: catalog)
        for model in catalog.models where active?.id != model.id && !queue.contains(model.id) {
            setState(scan(model), for: model.id)
        }
    }

    // MARK: Controls

    /// Starts or continues a download. Does nothing for a model that is finished, queued or downloading.
    public func start(_ id: String) {
        guard let model = catalog.model(id: id) else { return }
        if storage.isDownloaded(model) {
            setState(.downloaded, for: id)
            return
        }
        switch states[id] ?? .notDownloaded {
        case .queued, .downloading: return
        case .notDownloaded, .paused, .failed, .downloaded: break
        }
        let needed = max(0, model.totalBytes - storage.partialBytes(for: model)) + reserveBytes
        if let free = diskSpace.availableBytes(at: storage.root), free < needed {
            setState(.failed(.notEnoughSpace(needed: needed, available: free), progress(of: model)), for: id)
            return
        }
        queue.append(id)
        setState(.queued, for: id)
        pump()
    }

    /// Stops a download and keeps what arrived. Returns when the download has stopped.
    public func pause(_ id: String) async {
        guard let model = catalog.model(id: id) else { return }
        if let current = active, current.id == id {
            active?.stop = .pause
            current.task?.cancel()
            await current.task?.value
        } else if let index = queue.firstIndex(of: id) {
            queue.remove(at: index)
            setState(.paused(progress(of: model)), for: id)
        }
    }

    /// Stops a download and throws away what arrived. A finished model is left alone.
    public func cancel(_ id: String) async {
        guard let model = catalog.model(id: id) else { return }
        if let current = active, current.id == id {
            active?.stop = .cancel
            current.task?.cancel()
            await current.task?.value
            return
        }
        queue.removeAll { $0 == id }
        if states[id] != .downloaded {
            storage.removePartial(model)
            setState(.notDownloaded, for: id)
        }
    }

    /// Removes a model from the phone, whatever state it is in.
    public func delete(_ id: String) async throws {
        guard let model = catalog.model(id: id) else { return }
        await cancel(id)
        try storage.remove(model)
        setState(.notDownloaded, for: id)
    }

    /// Continues every download that stopped on a dropped connection. Call when the app becomes active again.
    public func resumeInterrupted() {
        for model in catalog.models {
            if case .failed(.network, _) = states[model.id] { start(model.id) }
        }
    }

    // MARK: Queue

    private func pump() {
        guard active == nil else { return }
        while !queue.isEmpty {
            let id = queue.removeFirst()
            guard let model = catalog.model(id: id) else { continue }
            let token = UUID()
            active = Active(id: id, token: token)
            active?.task = Task { await self.transfer(model, token: token) }
            return
        }
    }

    private func isActive(_ token: UUID) -> Bool {
        active?.token == token
    }

    private func end(_ token: UUID, _ state: OnDeviceModelState) {
        guard let current = active, current.token == token else { return }
        active = nil
        setState(state, for: current.id)
        pump()
    }

    // MARK: Transfer

    private func transfer(_ model: OnDeviceModel, token: UUID) async {
        guard isActive(token) else { return }
        var finished = storage.partialBytes(for: model)
        setState(
            .downloading(OnDeviceModelProgress(receivedBytes: finished, totalBytes: model.totalBytes)), for: model.id)
        do {
            try storage.preparePartialFolder(for: model)
            for (index, file) in model.files.enumerated() where !storage.hasPartialFile(file, of: model) {
                guard isActive(token) else { return }
                active?.fileIndex = index
                active?.baseBytes = finished
                active?.receivedBytes = finished
                active?.publishedBytes = finished
                let temporary = try await fetch(file, of: model, index: index, token: token)
                try storage.store(temporary, as: file, of: model)
                finished += file.bytes
                active?.receivedBytes = finished
                active?.publishedBytes = finished
                setState(
                    .downloading(OnDeviceModelProgress(receivedBytes: finished, totalBytes: model.totalBytes)),
                    for: model.id)
            }
            try storage.complete(model)
            end(token, .downloaded)
        } catch {
            conclude(token, model: model, error: error)
        }
    }

    /// Downloads one file, continuing from saved resume data when there is some for this file.
    private func fetch(
        _ file: OnDeviceModelFile, of model: OnDeviceModel, index: Int, token: UUID
    ) async throws -> URL {
        var resume = storage.resumeRecord(for: model).flatMap { $0.file == file.path ? $0.data : nil }
        storage.clearResumeRecord(for: model)
        let url = model.downloadURL(for: file)
        let report: @Sendable (Int64) -> Void = { [self] bytes in
            Task { await self.record(bytes, fileIndex: index, token: token) }
        }
        while true {
            do {
                return try await downloader.download(from: url, resumeData: resume, progress: report)
            } catch let stopped as ModelFileDownloadCancelled {
                save(stopped.resumeData, for: file, of: model)
                throw stopped
            } catch {
                if case ModelFileDownloadError.network(_, let data?) = error {
                    // The connection dropped part way: keep the part that arrived for the next try.
                    save(data, for: file, of: model)
                    throw error
                }
                if resume != nil && !Task.isCancelled {
                    // The system did not accept the resume data: start this file over, once.
                    resume = nil
                    continue
                }
                throw error
            }
        }
    }

    private func save(_ data: Data?, for file: OnDeviceModelFile, of model: OnDeviceModel) {
        guard let data, let current = active, current.id == model.id else { return }
        let inFlight = max(0, current.receivedBytes - current.baseBytes)
        storage.saveResumeRecord(
            OnDeviceModelResumeRecord(file: file.path, data: data, receivedBytes: inFlight), for: model)
    }

    /// Byte count from the downloader. It arrives out of order and after the file ended, so only the newest count for
    /// the file in flight is used.
    private func record(_ bytes: Int64, fileIndex: Int, token: UUID) {
        guard var current = active, current.token == token, current.fileIndex == fileIndex, current.stop == nil,
            let model = catalog.model(id: current.id), model.files.indices.contains(fileIndex)
        else { return }
        let total = current.baseBytes + min(max(0, bytes), model.files[fileIndex].bytes)
        guard total > current.receivedBytes else { return }
        current.receivedBytes = total
        if total - current.publishedBytes >= progressStep {
            current.publishedBytes = total
            setState(
                .downloading(OnDeviceModelProgress(receivedBytes: total, totalBytes: model.totalBytes)), for: model.id)
        }
        active = current
    }

    /// Settles the state after the transfer loop ended with an error.
    private func conclude(_ token: UUID, model: OnDeviceModel, error: Error) {
        guard let current = active, current.token == token else { return }
        switch current.stop {
        case .cancel:
            storage.removePartial(model)
            end(token, .notDownloaded)
        case .pause:
            end(token, .paused(progress(of: model)))
        case nil:
            if error is ModelFileDownloadCancelled {
                end(token, .paused(progress(of: model)))
            } else {
                end(token, .failed(failure(for: error), progress(of: model)))
            }
        }
    }

    private func failure(for error: Error) -> OnDeviceModelFailure {
        switch error {
        case ModelFileDownloadError.badStatus(let status): return .server(status: status)
        case ModelFileDownloadError.network(let message, _): return .network(message)
        case ModelFileDownloadError.fileSystem(let message): return .storage(message)
        case OnDeviceModelStorageError.sizeMismatch(let path, _, _): return .damaged(file: path)
        case OnDeviceModelStorageError.incomplete(let path): return .damaged(file: path)
        case OnDeviceModelStorageError.unsafePath(let path): return .damaged(file: path)
        case OnDeviceModelStorageError.fileSystem(let message): return .storage(message)
        default: return .network(error.localizedDescription)
        }
    }

    // MARK: State

    private func scan(_ model: OnDeviceModel) -> OnDeviceModelState {
        if storage.isDownloaded(model) { return .downloaded }
        if storage.hasPartialDownload(model) { return .paused(progress(of: model)) }
        return .notDownloaded
    }

    /// Bytes on the phone for a model that is not finished: finished files plus the part of the file in flight.
    private func progress(of model: OnDeviceModel) -> OnDeviceModelProgress {
        let received = storage.partialBytes(for: model) + (storage.resumeRecord(for: model)?.receivedBytes ?? 0)
        return OnDeviceModelProgress(receivedBytes: min(received, model.totalBytes), totalBytes: model.totalBytes)
    }

    private func setState(_ state: OnDeviceModelState, for id: String) {
        guard states[id] != state else { return }
        states[id] = state
        let update = OnDeviceModelUpdate(id: id, state: state)
        for continuation in subscribers.values { continuation.yield(update) }
    }

    private func removeSubscriber(_ key: UUID) {
        subscribers.removeValue(forKey: key)
    }
}
