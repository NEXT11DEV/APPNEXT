import Foundation

@main struct PerformanceChecks {
    static func main() throws {
        let measured = NextTransferSnapshot(received: 14_000_000, expected: 35_000_000)
        precondition(measured.percent == 40 && measured.fraction == 0.4)
        precondition(measured.notificationSubtitle.contains("40"))
        precondition(measured.notificationBody.contains(measured.bytesText))
        precondition(measured.notificationText.contains("40") && measured.notificationText.contains(measured.bytesText))
        precondition(measured.notificationText.contains(String(repeating: "▰", count: 4)))
        precondition(NextTransferSnapshot(received: 100, expected: -1).fraction == nil)
        precondition(NextTransferSnapshot(received: 100, expected: 0).percent == nil)
        precondition(NextTransferSnapshot(received: 120, expected: 100).percent == 100)
        precondition(NextTransferSnapshot(received: -1, expected: 100).percent == 0)
        print("PASS: HUD/notification snapshots use measured bytes, correct percentages, clamped progress and unknown totals without invented percentages")
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
        let releases = try source([["name":"Multi","bundleIdentifier":"com.multi","localizedDescription":"A real source description","versions":[["version":"2","downloadURL":"https://example.com/two.ipa","size":200],["version":"1","downloadURL":"https://example.com/one.ipa","size":100]]]])
        let original = releases.apps[0]
        let chosen = try original.selectingVersion(original.versions[1])
        precondition(chosen.version == "1" && chosen.downloadURL?.absoluteString == "https://example.com/one.ipa" && chosen.size == 100)
        precondition(chosen.localizedDescription == original.localizedDescription && chosen.bundleIdentifier == original.bundleIdentifier)
        precondition(original.version == "2")
        print("PASS: selected historical version uses its own URL and size while preserving description and identifier")
        let removed = NextCatalogIndex.flatten(repositories: [b], catalog: [a.id: primary,b.id: secondary])
        precondition(removed.count == 2 && removed[0].name == "Duplicate")
        let firstPage = NextCatalogIndex.page(index, query: "", category: "الكل")
        precondition(firstPage.apps.count == 30 && firstPage.hasMore)
        let secondPage = NextCatalogIndex.page(index, query: "", category: "الكل", limit: 60)
        precondition(secondPage.apps.count == 60 && secondPage.hasMore)
        precondition(Array(secondPage.apps.prefix(30)) == firstPage.apps)
        let lastPage = NextCatalogIndex.page(index, query: "", category: "الكل", limit: 12_030)
        precondition(lastPage.apps == index && !lastPage.hasMore)
        let search = NextCatalogIndex.page(index, query: "aPP 1", category: "الكل")
        precondition(search.apps.count == 30 && search.hasMore)
        let nextSearch = NextCatalogIndex.page(index, query: "aPP 1", category: "الكل", limit: 60)
        precondition(nextSearch.apps.count == 60 && Array(nextSearch.apps.prefix(30)) == search.apps)
        let lateMatch = NextCatalogIndex.page(index, query: "aPP 11999", category: "الكل")
        precondition(lateMatch.apps.map(\.name) == ["App 11999"] && !lateMatch.hasMore)
        let games = NextCatalogIndex.page(index, query: "", category: "ألعاب")
        precondition(games.apps.count == 30 && games.hasMore)
        precondition(games.apps.allSatisfy { ($0.category ?? "").lowercased().contains("game") })
        let empty = NextCatalogIndex.page(index, query: "no-such-app", category: "الكل")
        precondition(empty.apps.isEmpty && !empty.hasMore)
        precondition(NextCatalogIndex.page([], query: "", category: "الكل").apps.isEmpty)
        print("PASS: initial and search pages are 30, scrolling extends by 30 without gaps, late catalog results remain searchable, categories and final/empty pages work")
        print("PASS: 10,000 progress callbacks reduced to \(emissions) interim UI updates plus completion")
        print("PASS: 12,001-app catalog preserves source priority, deduplicates, searches and filters correctly")
    }
}

