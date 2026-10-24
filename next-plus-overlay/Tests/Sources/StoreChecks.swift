import Foundation

@main struct StoreChecks {
    @MainActor static func main() async throws {
        let store = RepositoryStore()
        let builtin = try XCTUnwrap(store.repositories.first { NextDefaultSources.isBuiltIn($0) })
        store.remove(builtin)
        precondition(store.repositories.contains { $0.id == builtin.id })
        precondition(!store.visibleRepositories.contains { $0.id == builtin.id })
        while !store.catalogCacheLoaded { try await Task.sleep(nanoseconds: 20_000_000) }
        precondition(store.catalog[builtin.id]?.apps.count == 20419)
        let custom: Repository
        switch store.add(urlString: "https://example.com/idk-test-\(UUID().uuidString).json") {
        case .success(let value): custom = value
        case .failure: fatalError("custom source insertion failed")
        }
        precondition(store.visibleRepositories.contains(custom))
        store.remove(custom)
        precondition(!store.repositories.contains(custom))
        precondition(store.catalog[builtin.id]?.apps.count == 20419)
        print("PASS: actual RepositoryStore blocks built-in deletion, loads the shipped catalog offline, permits custom source management")
    }
    private static func XCTUnwrap<T>(_ value: T?) throws -> T {
        guard let value else { throw NSError(domain: "idk-test", code: 1) }
        return value
    }
}
