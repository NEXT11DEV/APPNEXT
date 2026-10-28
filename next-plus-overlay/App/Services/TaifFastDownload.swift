import Foundation
import CryptoKit

/// Ranges are used only with an origin validator. A changed or nonconforming
/// response is discarded in full before a normal streaming download is attempted.
struct TaifByteRange: Sendable {
    let start: Int64
    let end: Int64
    let total: Int64
    let validatorHeader: String
    let validator: String
    var length: Int64 { end - start + 1 }
    var contentRange: String { "bytes \(start)-\(end)/\(total)" }
}

private final class TaifRangeProgress: @unchecked Sendable {
    private let lock = NSLock()
    private var received = [Int: Int64]()
    private var throttle = NextProgressThrottle()
    private let expected: Int64
    private let callback: @Sendable (NextTransferSnapshot) -> Void
    init(expected: Int64, callback: @escaping @Sendable (NextTransferSnapshot) -> Void) {
        self.expected = expected; self.callback = callback
    }
    func update(_ index: Int, bytes: Int64) {
        lock.lock()
        received[index] = bytes
        let total = received.values.reduce(0, +)
        let emit = throttle.shouldEmit(at: ProcessInfo.processInfo.systemUptime, completed: total == expected)
        lock.unlock()
        if emit { callback(NextTransferSnapshot(received: total, expected: expected)) }
    }
}

enum TaifFastDownload {
    static let maximumSize: Int64 = 2_147_483_648

    static func ranges(size: Int64, validatorHeader: String, validator: String) -> [TaifByteRange] {
        guard size >= 16 * 1024 * 1024 && size <= maximumSize else { return [] }
        let width = (size + 3) / 4
        return (0..<4).map { index in
            TaifByteRange(start: Int64(index) * width, end: min(size - 1, Int64(index + 1) * width - 1),
                          total: size, validatorHeader: validatorHeader, validator: validator)
        }
    }

    static func run(url: URL, destination: URL, cacheIdentity: String, expectedSize: Int64? = nil, allowParallel: Bool = false,
                    progress: @escaping @Sendable (NextTransferSnapshot) -> Void,
                    route: @escaping @Sendable (String) -> Void) async throws -> URL {
        let cache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TAIF-IPA", isDirectory: true)
        let key = SHA256.hash(data: Data((url.absoluteString + "\n" + cacheIdentity).utf8)).map { String(format: "%02x", $0) }.joined()
        let cached = cache.appendingPathComponent(key + ".ipa")
        if (try? await Task.detached(priority: .userInitiated, operation: { () -> Bool in
            guard let values = try? cached.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modified = values.contentModificationDate, Date().timeIntervalSince(modified) < 86400,
                  (values.fileSize ?? 0) > 4 else { return false }
            let input = try FileHandle(forReadingFrom: cached)
            defer { try? input.close() }
            guard try input.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]) else { return false }
            try Task.checkCancellation()
            try FileManager.default.copyItem(at: cached, to: destination)
            return true
        }).value) == true {
            try Task.checkCancellation()
            route("استُخدمت نسخة IPA الأصلية المحفوظة مؤقتًا؛ بدون إعادة تنزيل")
            let bytes = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            progress(NextTransferSnapshot(received: bytes, expected: bytes))
            return destination
        }

        try Task.checkCancellation()
        try? FileManager.default.removeItem(at: destination)
        let directory = destination.deletingLastPathComponent().appendingPathComponent("ranges-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var usedParallel = false
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        let probe = URLSession(configuration: config)
        defer { probe.invalidateAndCancel() }
        do {
            guard allowParallel && (expectedSize ?? 0) >= 16 * 1024 * 1024 else { throw URLError(.unsupportedURL) }
            var head = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            head.httpMethod = "HEAD"
            head.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
            let (_, response) = try await probe.data(for: head)
            try Task.checkCancellation()
            if let response = response as? HTTPURLResponse, response.statusCode == 200,
               response.value(forHTTPHeaderField: "Accept-Ranges")?.lowercased() == "bytes",
               let length = response.value(forHTTPHeaderField: "Content-Length").flatMap(Int64.init),
               let finalURL = response.url, ["https", "http"].contains(finalURL.scheme?.lowercased() ?? "") {
                let etag = response.value(forHTTPHeaderField: "ETag")
                // Last-Modified dates can collide when a source replaces a file
                // twice in one second; require a strong ETag for safe assembly.
                if let etag, etag.hasPrefix("\""), etag.hasSuffix("\""),
                   !ranges(size: length, validatorHeader: "ETag", validator: etag).isEmpty {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let plan = ranges(size: length, validatorHeader: "ETag", validator: etag)
                    let meter = TaifRangeProgress(expected: length, callback: progress)
                    route("تنزيل متوازٍ: 4 أجزاء متحققة من نفس إصدار الملف")
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        for (index, range) in plan.enumerated() {
                            group.addTask {
                                var request = URLRequest(url: finalURL, cachePolicy: .reloadIgnoringLocalCacheData)
                                request.setValue("bytes=\(range.start)-\(range.end)", forHTTPHeaderField: "Range")
                                request.setValue(range.validator, forHTTPHeaderField: "If-Range")
                                request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                                _ = try await NextIPADownload().run(request: request,
                                    destination: directory.appendingPathComponent(String(index)), range: range) { value in
                                    meter.update(index, bytes: value.received)
                                }
                            }
                        }
                        for try await _ in group { }

                    }
                    try await Task.detached(priority: .userInitiated) {
                        try assemble(directory: directory, destination: destination, plan: plan)
                    }.value
                    usedParallel = true
                }
            }
        } catch {
            try Task.checkCancellation()
            try? FileManager.default.removeItem(at: destination)
            if allowParallel && (expectedSize ?? 0) >= 16 * 1024 * 1024 { route("المصدر لم يقبل الأجزاء بأمان؛ الرجوع لتنزيل مباشر") }
        }
        try Task.checkCancellation()
        if !usedParallel {
            route("تنزيل مباشر من المصدر")
            _ = try await NextIPADownload().run(url: url, destination: destination, progress: progress)
        }
        try Task.checkCancellation()
        // Bounded disposable cache. No signed output or certificates live here.
        await Task.detached(priority: .utility) {
            do {
                try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
                let files = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
                let size = Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
                var budget = size
                for file in files.sorted(by: { ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) }) {
                    let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                    budget += Int64(values.fileSize ?? 0)
                    if budget > maximumSize || Date().timeIntervalSince(values.contentModificationDate ?? .distantPast) > 86400 { try? FileManager.default.removeItem(at: file) }
                }
                if size <= maximumSize {
                    try? FileManager.default.removeItem(at: cached)
                    try FileManager.default.copyItem(at: destination, to: cached)
                }
            } catch { /* Cache failure must never block an otherwise valid IPA. */ }
        }.value
        return destination
    }

    static func assemble(directory: URL, destination: URL, plan: [TaifByteRange]) throws {
        guard !plan.isEmpty else { throw URLError(.badServerResponse) }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        for (index, range) in plan.enumerated() {
            try Task.checkCancellation()
            let source = directory.appendingPathComponent(String(index))
            guard Int64((try source.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) == range.length else { throw URLError(.badServerResponse) }
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            while let bytes = try input.read(upToCount: 1024 * 1024), !bytes.isEmpty { try output.write(contentsOf: bytes) }
        }
        let input = try FileHandle(forReadingFrom: destination)
        defer { try? input.close() }
        guard try input.read(upToCount: 4) == Data([0x50, 0x4b, 0x03, 0x04]),
              Int64((try destination.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0) == plan[0].total else { throw URLError(.badServerResponse) }
    }
}
