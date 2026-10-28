import Foundation

/// Streams IPA bytes to disk with real progress. Cancellation closes the network
/// task and resumes its continuation; no task is left permanently busy.
final class NextIPADownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var range: TaifByteRange?
    private var progressThrottle = NextProgressThrottle()
    private var session: URLSession?
    private var progress: (@Sendable (NextTransferSnapshot) -> Void)?

    func run(url: URL, destination: URL, progress: @escaping @Sendable (NextTransferSnapshot) -> Void) async throws -> URL {
        try await run(request: URLRequest(url: url), destination: destination, range: nil, progress: progress)
    }

    func run(request: URLRequest, destination: URL, range: TaifByteRange?, progress: @escaping @Sendable (NextTransferSnapshot) -> Void) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                self.destination = destination
                self.range = range
                self.progress = progress
                self.progressThrottle = NextProgressThrottle()
                lock.unlock()
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 45
                config.timeoutIntervalForResource = 1800
                config.httpMaximumConnectionsPerHost = 4
                config.urlCache = nil
                config.requestCachePolicy = .reloadIgnoringLocalCacheData
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                lock.lock(); self.session = session; lock.unlock()
                if Task.isCancelled { cancel(); return }
                let task = session.downloadTask(with: request)
                task.priority = URLSessionTask.highPriority
                task.resume()
            }
        } onCancel: { self.cancel() }
    }

    func cancel() {
        lock.lock(); let session = session; lock.unlock()
        session?.invalidateAndCancel()
        finish(.failure(CancellationError()))
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let session = session
        self.session = nil
        progress = nil
        lock.unlock()
        continuation?.resume(with: result)
        session?.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > (range?.length ?? 2_147_483_648) { cancel(); return }
        let completed = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        lock.lock()
        let callback = progressThrottle.shouldEmit(at: ProcessInfo.processInfo.systemUptime, completed: completed) ? progress : nil
        lock.unlock()
        callback?(NextTransferSnapshot(received: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse else {
                throw NSError(domain: "NEXT", code: 1, userInfo: [NSLocalizedDescriptionKey: "رابط التطبيق لم يرجع ملفًا صالحًا. جرّب مصدرًا أو إصدارًا آخر."])
            }
            let bytes = Int64((try location.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            if let range {
                guard response.statusCode == 206,
                      response.value(forHTTPHeaderField: "Content-Range") == range.contentRange,
                      bytes == range.length,
                      response.value(forHTTPHeaderField: range.validatorHeader) == range.validator else {
                    throw URLError(.badServerResponse)
                }
            } else {
                guard response.statusCode == 200 else { throw URLError(.badServerResponse) }
                let handle = try FileHandle(forReadingFrom: location)
                let signature = try handle.read(upToCount: 4)
                try handle.close()
                guard signature == Data([0x50, 0x4b, 0x03, 0x04]) else {
                    throw NSError(domain: "TAIF", code: 2, userInfo: [NSLocalizedDescriptionKey: "الرابط رجّع صفحة أو ملفًا غير IPA، لذلك لم يبدأ التوقيع."])
                }
                if response.expectedContentLength > 0 && bytes != response.expectedContentLength { throw URLError(.networkConnectionLost) }
            }
            lock.lock(); let target = destination; lock.unlock()
            guard let target else { throw CancellationError() }
            try FileManager.default.moveItem(at: location, to: target)
            finish(.success(target))
        } catch { finish(.failure(error)) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { finish(.failure(error)) }
    }
}


