import Foundation

/// Build list data when catalog/search inputs change, independently of signing
/// progress. Preserve repository order and the first app for each identifier.
enum NextCatalogIndex {
    static func flatten(repositories: [Repository], catalog: [UUID: RepoSource]) -> [RepoApp] {
        var seen = Set<String>()
        var apps: [RepoApp] = []
        for repository in repositories {
            guard let source = catalog[repository.id] else { continue }
            for app in source.apps where seen.insert(app.id).inserted { apps.append(app) }
        }
        return apps
    }

    static func filter(_ apps: [RepoApp], query: String, category: String) -> [RepoApp] {
        guard !query.isEmpty || category != "الكل" else { return apps }
        return apps.filter { app in
            if !query.isEmpty && !app.name.localizedCaseInsensitiveContains(query) { return false }
            let value = app.category ?? ""
            let isGame = value.lowercased().contains("game") || value.contains("ألعاب")
            return category == "الكل" || (category == "ألعاب" ? isGame : !isGame)
        }
    }
}


struct NextCatalogPage: Sendable {
    let apps: [RepoApp]
    let hasMore: Bool
}

extension NextCatalogIndex {
    static let pageSize = 30

    /// Search the whole catalog but retain only the requested visible window.
    /// One additional match tells the UI whether another page exists.
    static func page(_ apps: [RepoApp], query: String, category: String,
                     limit: Int = pageSize) -> NextCatalogPage {
        let count = max(0, limit)
        var visible: [RepoApp] = []
        visible.reserveCapacity(min(count, apps.count))
        for app in apps {
            if !query.isEmpty && !app.name.localizedCaseInsensitiveContains(query) { continue }
            let categoryValue = app.category ?? ""
            let isGame = categoryValue.lowercased().contains("game") || categoryValue.contains("ألعاب")
            if category != "الكل" && (category == "ألعاب" ? !isGame : isGame) { continue }
            if visible.count == count { return NextCatalogPage(apps: visible, hasMore: true) }
            visible.append(app)
        }
        return NextCatalogPage(apps: visible, hasMore: false)
    }
}
