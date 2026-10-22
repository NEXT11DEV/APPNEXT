import Foundation

@main struct Checks {
    static func main() async throws {
        let future = Date().addingTimeInterval(3600)
        precondition(NextSigningPolicy.credentials(certificateExpiry: nil, profileExpiry: future, certificateTeam: nil, profileTeam: nil) != nil)
        precondition(NextSigningPolicy.credentials(certificateExpiry: .distantPast, profileExpiry: future, certificateTeam: "A", profileTeam: "A") != nil)
        precondition(NextSigningPolicy.credentials(certificateExpiry: future, profileExpiry: future, certificateTeam: "A", profileTeam: "B") != nil)
        precondition(NextSigningPolicy.credentials(certificateExpiry: future, profileExpiry: future, certificateTeam: "A", profileTeam: "A") == nil)
        precondition(NextSigningPolicy.allows(bundleID: "app.nextplus.test", applicationIdentifier: "TEAM.*"))
        precondition(NextSigningPolicy.allows(bundleID: "app.nextplus.test", applicationIdentifier: "TEAM.app.nextplus.*"))
        precondition(!NextSigningPolicy.allows(bundleID: "app.other.test", applicationIdentifier: "TEAM.app.nextplus.*"))
        precondition(!NextSigningPolicy.allows(bundleID: "app.nextplus.test2", applicationIdentifier: "TEAM.app.nextplus.test"))
        for invalid in ["bytes=99-100", "bytes=4-2", "bytes=a-", "bytes=0-3,4-6", "bytes=-0", "bytes=0-x"] {
            precondition(NextSigningPolicy.byteRange(invalid, size: 10) == nil)
        }
        precondition(NextSigningPolicy.byteRange("bytes=-3", size: 10)?.start == 7)
        precondition(NextSigningPolicy.byteRange("bytes=3-", size: 10)?.end == 9)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("test.ipa")
        let bytes = Data((0..<10000).map { UInt8($0 % 251) })
        try bytes.write(to: file)
        let server = LocalInstallServer()
        _ = try await server.start(ipa: file, bundleId: "app.nextplus.test", bundleVersion: "1", title: "Test")
        defer { server.stop() }
        let url = URL(string: server.payloadURL)!
        let (all, response) = try await URLSession.shared.data(from: url)
        precondition(all == bytes && (response as? HTTPURLResponse)?.statusCode == 200)
        var head = URLRequest(url: url); head.httpMethod = "HEAD"
        let (empty, metadata) = try await URLSession.shared.data(for: head)
        precondition(empty.isEmpty && (metadata as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Length") == "10000")
        for (value, expected) in [("bytes=10-19", Data(bytes[10...19])), ("bytes=9990-", Data(bytes[9990...])), ("bytes=-12", Data(bytes.suffix(12)))] {
            var request = URLRequest(url: url); request.setValue(value, forHTTPHeaderField: "Range")
            let (body, info) = try await URLSession.shared.data(for: request)
            precondition(body == expected && (info as? HTTPURLResponse)?.statusCode == 206)
        }
        var invalid = URLRequest(url: url); invalid.setValue("bytes=10000-", forHTTPHeaderField: "Range")
        let (_, rejected) = try await URLSession.shared.data(for: invalid)
        precondition((rejected as? HTTPURLResponse)?.statusCode == 416)
        precondition(FileManager.default.fileExists(atPath: file.path))
        print("PASS: credential policy, bundle permissions, real HTTP GET/HEAD/ranges/416, file retention")
    }
}
