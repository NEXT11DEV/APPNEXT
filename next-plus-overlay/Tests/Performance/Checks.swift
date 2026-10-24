import Foundation

@main struct PerformanceChecks {
    static func main() throws {
        var throttle = NextProgressThrottle()
        var emissions = 0
        for tick in 0..<10_000 {
            if throttle.shouldEmit(at: Double(tick) / 1_000) { emissions += 1 }
        }
        precondition((40...52).contains(emissions), "Progress must be bounded near five updates/second")
        precondition(throttle.shouldEmit(at: 10, completed: true), "Always retain final update")
        var first = NextProgressThrottle()
        precondition(first.shouldEmit(at: 0))
        precondition(!first.shouldEmit(at: 0.01))
        precondition(first.shouldEmit(at: 0.02, completed: true))

        let rows: [[String: Any]] = (0..<12_000).map {
            ["name": "App \($0)", "bundleIdentifier": "app.example.\($0)", "category": $0 % 2 == 0 ? "Games" : "Utilities"]
        }
        func source(_ apps: [[String: Any]]) throws -> RepoSource {
            try JSONDecoder().decode(RepoSource.self, from: JSONSerialization.data(withJSONObject: ["apps": apps]))
        }
        let a = Repository(url: URL(string: "https://example.com/a.json")!, name: "A")
        let b = Repository(url: URL(string: "https://example.com/b.json")!, name: "B")
        let primary = try source(rows)
        let secondary = try source([
            ["name": "Duplicate", "bundleIdentifier": "app.example.0", "category": "Games"],
            ["name": "Arabic Game", "bundleIdentifier": "app.example.extra", "category": "ألعاب"]
        ])
        let index = NextCatalogIndex.flatten(repositories: [a,b], catalog: [a.id: primary,b.id: secondary])
        precondition(index.count == 12_001 && index[0].name == "App 0" && index.last?.name == "Arabic Game")
        precondition(NextCatalogIndex.filter(index, query: "aPP 11999", category: "الكل").map(\.name) == ["App 11999"])
        precondition(NextCatalogIndex.filter(index, query: "", category: "ألعاب").count == 6_001)
        precondition(NextCatalogIndex.filter(index, query: "", category: "تطبيقات").count == 6_000)
        precondition(NextCatalogIndex.filter(index, query: "Arabic", category: "ألعاب").count == 1)
        let removed = NextCatalogIndex.flatten(repositories: [b], catalog: [a.id: primary,b.id: secondary])
        precondition(removed.count == 2 && removed[0].name == "Duplicate")
        print("PASS: 10,000 progress callbacks reduced to \(emissions) interim UI updates plus completion")
        print("PASS: 12,001-app catalog preserves source priority, deduplicates, searches and filters correctly")
    }
}

