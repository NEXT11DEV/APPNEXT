import Foundation

@main struct SourceChecks {
    static func main() throws {
        var fresh: [Repository] = []
        precondition(NextDefaultSources.seed(in: &fresh))
        precondition(fresh.count == 1 && fresh[0].id == NextDefaultSources.ownerID)
        precondition(!NextDefaultSources.seed(in: &fresh))
        precondition(NextDefaultSources.visible(fresh).isEmpty)
        precondition(!NextDefaultSources.canRemove(fresh[0]))
        let custom = Repository(url: URL(string: "https://example.com/user-source.json")!, name: "Custom")
        var upgraded = [custom]
        precondition(NextDefaultSources.seed(in: &upgraded))
        precondition(upgraded.count == 2 && upgraded[1] == custom)
        precondition(NextDefaultSources.visible(upgraded) == [custom])
        precondition(NextDefaultSources.canRemove(custom))
        let duplicate = Repository(url: NextDefaultSources.ownerURL, name: "Duplicate")
        upgraded.append(duplicate)
        precondition(NextDefaultSources.seed(in: &upgraded))
        precondition(upgraded.count == 2 && upgraded[0].id == NextDefaultSources.ownerID)
        // Even a malformed saved record cannot expose the built-in URL as removable.
        precondition(!NextDefaultSources.canRemove(duplicate))
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let raw = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let rawApps = raw["apps"] as! [[String: Any]]
        let decoded = try JSONDecoder().decode(RepoSource.self, from: data)
        precondition(rawApps.count == 20419 && decoded.apps.count == rawApps.count)
        precondition(decoded.name == "idk plus")
        precondition(decoded.apps.allSatisfy { $0.downloadURL != nil })
        print("PASS: built-in catalog is seeded, hidden, protected from removal, normalized on upgrade; all \(decoded.apps.count) attached catalog entries decode")
    }
}
