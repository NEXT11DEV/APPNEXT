import Foundation

@main struct SourceChecks {
    static func main() throws {
        var fresh: [Repository] = []
        precondition(NextDefaultSources.seed(in: &fresh))
        precondition(fresh.count == 1 && fresh[0].url == NextDefaultSources.ownerURL)
        precondition(!NextDefaultSources.seed(in: &fresh) && fresh.count == 1)
        let custom = Repository(url: URL(string: "https://example.com/user-source.json")!, name: "Custom")
        var upgraded = [custom]
        precondition(NextDefaultSources.seed(in: &upgraded))
        precondition(upgraded.count == 2 && upgraded[0] == custom)
        let existing = Repository(url: NextDefaultSources.ownerURL, name: "Previously added")
        var manual = [custom, existing]
        precondition(!NextDefaultSources.seed(in: &manual) && manual == [custom, existing])
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rawApps = raw["apps"] as! [[String: Any]]
        let decoded = try JSONDecoder().decode(RepoSource.self, from: data)
        precondition(!decoded.apps.isEmpty && decoded.apps.count == rawApps.count)
        precondition(decoded.apps.contains { $0.downloadURL != nil })
        print("PASS: default source on fresh/upgrade/manual installs; preserves user sources; decodes all \(decoded.apps.count) live catalog entries")
    }
}
