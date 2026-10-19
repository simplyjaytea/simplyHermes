import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Downloads one file. The download manager calls it once per model file, so tests can script it.
public protocol ModelFileDownloader: Sendable {
    /// Downloads `url` to a temporary file and returns where it is. The caller owns the file and moves it.
    ///
    /// `resumeData` continues an earlier, stopped download of the same URL. `progress` is called with the number of
    /// bytes received so far for this file, counting those a resume already had; it may be called from any thread.
    ///
    /// When the calling task is cancelled the download stops and this throws ``ModelFileDownloadCancelled``, carrying
    /// resume data when the system produced some. Any other failure throws ``ModelFileDownloadError``.
    func download(
        from url: URL, resumeData: Data?, progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL
}

/// A download was stopped on purpose (pause or cancel).
public struct ModelFileDownloadCancelled: Error, Sendable, Equatable {
    /// What a later download needs to continue where this one stopped, if the system produced it.
    public var resumeData: Data?

    public init(resumeData: Data? = nil) {
        self.resumeData = resumeData
    }
}

/// A download failed.
public enum ModelFileDownloadError: Error, Sendable, Equatable {
    /// The server answered with a status other than 2xx.
    case badStatus(Int)
    /// The connection failed or dropped. `resumeData` continues the file when the system kept the part it had.
    case network(String, resumeData: Data?)
    /// The finished file could not be moved out of the system's temporary folder.
    case fileSystem(String)
}

/// Downloads with `URLSession` download tasks, which stream to disk instead of memory.
///
/// One foreground session: a download runs while the app is open. When iOS drops the connection after the app
/// goes to the background, the error carries resume data and the manager continues the file when asked.
public final class URLSessionModelFileDownloader: NSObject, ModelFileDownloader, @unchecked Sendable {
    private final class Transfer: @unchecked Sendable {
        let progress: @Sendable (Int64) -> Void
        var continuation: CheckedContinuation<URL, Error>?

        init(progress: @escaping @Sendable (Int64) -> Void) {
            self.progress = progress
        }
    }

    /// Lets the cancellation handler reach the task, even when cancellation arrives before the task exists.
    private final class TaskBox: @unchecked Sendable {
        private let lock = NSLock()
        private var task: URLSessionDownloadTask?
        private var isCancelled = false

        /// Stores the task. Returns false when cancellation already happened, so the caller must not start it.
        func set(_ task: URLSessionDownloadTask) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            self.task = task
            return !isCancelled
        }

        func cancel(_ finish: @escaping @Sendable (URLSessionTask, Data?) -> Void) {
            lock.lock()
            isCancelled = true
            let task = self.task
            lock.unlock()
            guard let task else { return }
            task.cancel(byProducingResumeData: { data in finish(task, data) })
        }
    }

    private let lock = NSLock()
    private var transfers: [Int: Transfer] = [:]
    private var session: URLSession?

    /// A session that waits for a connection instead of failing at once, with no URL cache (the files are large).
    public init(configuration: URLSessionConfiguration = URLSessionModelFileDownloader.defaultConfiguration()) {
        super.init()
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    public static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        #if canImport(Darwin)
            configuration.waitsForConnectivity = true
        #endif
        return configuration
    }

    public func download(
        from url: URL, resumeData: Data?, progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> URL {
        guard let session else { throw ModelFileDownloadError.fileSystem("The download session is closed.") }
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let task =
                    resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
                let transfer = Transfer(progress: progress)
                transfer.continuation = continuation
                lock.withLock { transfers[task.taskIdentifier] = transfer }
                if box.set(task) {
                    task.resume()
                } else {
                    finish(task, .failure(ModelFileDownloadCancelled()))
                }
            }
        } onCancel: {
            box.cancel { [self] task, data in finish(task, .failure(ModelFileDownloadCancelled(resumeData: data))) }
        }
    }

    /// Ends a transfer once. Later calls for the same task do nothing.
    private func finish(_ task: URLSessionTask, _ result: Result<URL, Error>) {
        let transfer = lock.withLock { transfers.removeValue(forKey: task.taskIdentifier) }
        guard let continuation = transfer?.continuation else { return }
        transfer?.continuation = nil
        continuation.resume(with: result)
    }

    private func progress(for task: URLSessionTask) -> (@Sendable (Int64) -> Void)? {
        lock.withLock { transfers[task.taskIdentifier]?.progress }
    }

    /// The resume data the system attached to a failure, where the platform provides it.
    private static func resumeData(from error: Error) -> Data? {
        #if canImport(Darwin)
            return (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        #else
            return nil
        #endif
    }
}

extension URLSessionModelFileDownloader: URLSessionDownloadDelegate {
    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        progress(for: downloadTask)?(totalBytesWritten)
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            finish(downloadTask, .failure(ModelFileDownloadError.badStatus(http.statusCode)))
            return
        }
        // The system deletes `location` when this method returns, so the file moves out now.
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(
            "model-download-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            finish(downloadTask, .success(destination))
        } catch {
            finish(downloadTask, .failure(ModelFileDownloadError.fileSystem(error.localizedDescription)))
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let data = Self.resumeData(from: error)
        if (error as? URLError)?.code == .cancelled {
            finish(task, .failure(ModelFileDownloadCancelled(resumeData: data)))
        } else {
            finish(task, .failure(ModelFileDownloadError.network(error.localizedDescription, resumeData: data)))
        }
    }
}
