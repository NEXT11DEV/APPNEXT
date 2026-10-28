import Foundation
import CryptoKit

private final class Samples: @unchecked Sendable {
    let lock = NSLock()
    var values: [NextTransferSnapshot] = []
    var routes: [String] = []
    func append(_ value: NextTransferSnapshot) { lock.lock(); values.append(value); lock.unlock() }
    func append(_ route: String) { lock.lock(); routes.append(route); lock.unlock() }
}

@main struct DownloadChecks {
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let size: Int64 = 17 * 1024 * 1024 + 37
        let plan = TaifFastDownload.ranges(size: size, validatorHeader: "ETag", validator: "\"fixture-v1\"")
        precondition(plan.count == 4 && plan.first?.start == 0 && plan.last?.end == size - 1)
        precondition(plan.reduce(0) { $0 + $1.length } == size)
        for i in 1..<plan.count { precondition(plan[i].start == plan[i-1].end + 1) }
        precondition(TaifFastDownload.ranges(size: 100, validatorHeader: "ETag", validator: "v").isEmpty)
        let identity = UUID().uuidString
        var expected = Data([0x50,0x4b,0x03,0x04]);expected.append(Data(repeating: 37, count: Int(size)-4))
        let hash = SHA256.hash(data: expected)
        for path in ["parallel", "ignored", "changed", "truncated", "ordinary"] {
            let meter = Samples()
            let target = root.appendingPathComponent(path + ".ipa")
            let result = try await TaifFastDownload.run(url: base.appendingPathComponent(path), destination: target,
                cacheIdentity: identity, expectedSize: size, progress: { meter.append($0) }, route: { meter.append($0) })
            let actualHash = SHA256.hash(data: try Data(contentsOf: result))
            precondition(actualHash == hash, "Must never assemble corrupt or mixed data: " + path)
            precondition(meter.values.allSatisfy { $0.received >= 0 && $0.received <= size })
            if path == "parallel" {
                precondition(meter.routes.contains { $0.contains("4") })
                let cached = root.appendingPathComponent("cached.ipa"), samples = Samples()
                _ = try await TaifFastDownload.run(url: base.appendingPathComponent(path), destination: cached,
                    cacheIdentity: identity, expectedSize: size, progress: { samples.append($0) }, route: { samples.append($0) })
                precondition(samples.routes.contains { $0.contains("بدون إعادة تنزيل") })
                let cachedHash = SHA256.hash(data: try Data(contentsOf: cached))
                precondition(cachedHash == hash)
            }
        }
        do {
            _ = try await TaifFastDownload.run(url: base.appendingPathComponent("html"), destination: root.appendingPathComponent("bad.ipa"), cacheIdentity: identity, progress: { _ in }, route: { _ in })
            preconditionFailure("HTML must not be signed")
        } catch { }
        let task = Task {
            try await TaifFastDownload.run(url: base.appendingPathComponent("slow"), destination: root.appendingPathComponent("slow.ipa"), cacheIdentity: identity, expectedSize: size, progress: { _ in }, route: { _ in })
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        do { _ = try await task.value; preconditionFailure("Cancellation must terminate transfer") }
        catch { }
        print("PASS: four ranges without gaps, byte-identical assembly, ignored/changed/truncated range fallback, no-network cache reuse, HTML rejection and cancellation")
    }
}
