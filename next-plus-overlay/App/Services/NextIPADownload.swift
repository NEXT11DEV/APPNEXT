import Foundation

/// Streams IPA bytes to disk with real progress. Cancellation closes the network
/// task and resumes its continuation; no task is left permanently busy.
final class NextIPADownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var destination: URL?
    private var progressThrottle = NextProgressThrottle()
    private var session: URLSession?
    private var progress: (@Sendable (Double?) -> Void)?

    func run(url: URL, destination: URL, progress: @escaping @Sendable (Double?) -> Void) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                self.destination = destination
                self.progress = progress
                self.progressThrottle = NextProgressThrottle()
                lock.unlock()
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 45
                config.timeoutIntervalForResource = 600
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                lock.lock(); self.session = session; lock.unlock()
                if Task.isCancelled { cancel(); return }
                session.downloadTask(with: url).resume()
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
        if totalBytesWritten > 2_147_483_648 { cancel(); return }
        let completed = totalBytesExpectedToWrite > 0 && totalBytesWritten >= totalBytesExpectedToWrite
        lock.lock()
        let callback = progressThrottle.shouldEmit(at: ProcessInfo.processInfo.systemUptime, completed: completed) ? progress : nil
        lock.unlock()
        callback?(totalBytesExpectedToWrite > 0 ? min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) : nil)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200 else {
                throw NSError(domain: "NEXT", code: 1, userInfo: [NSLocalizedDescriptionKey: "رابط التطبيق لم يرجع ملفًا صالحًا. جرّب مصدرًا أو إصدارًا آخر."])
            }
            let handle = try FileHandle(forReadingFrom: location)
            let signature = try handle.read(upToCount: 4)
            try handle.close()
            guard signature == Data([0x50, 0x4b, 0x03, 0x04]) else {
                throw NSError(domain: "NEXT", code: 2, userInfo: [NSLocalizedDescriptionKey: "الرابط رجّع صفحة أو ملفًا غير IPA، لذلك لم يبدأ التوقيع."])
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

