import Foundation

/// A versioned catalog shipped with the app, independent of a remote host.
/// It participates in indexing but is never a user-editable repository.
enum NextDefaultSources {
    static let ownerURL = URL(string: "taifplus-bundled://catalog")!
    static let ownerID = UUID(uuidString: "082BDE50-10DA-4097-8494-220C8B3A2B96")!

    static func isBuiltIn(_ repository: Repository) -> Bool {
        repository.id == ownerID || repository.url == ownerURL
    }

    static func visible(_ repositories: [Repository]) -> [Repository] {
        repositories.filter { !isBuiltIn($0) }
    }

    static func canRemove(_ repository: Repository) -> Bool { !isBuiltIn(repository) }

    @discardableResult
    static func seed(in repositories: inout [Repository]) -> Bool {
        let original = repositories
        // Normalize the stable identity, repair missing records, remove duplicates.
        repositories.removeAll { isBuiltIn($0) }
        repositories.insert(Repository(id: ownerID, url: ownerURL, name: "TAIF PLUS",
                                       addedAt: Date(timeIntervalSince1970: 0)), at: 0)
        return repositories != original
    }

    static func bundledData(in bundle: Bundle = .main) throws -> Data {
        guard let url = bundle.url(forResource: "TAIFPlusCatalog", withExtension: "json") else {
            throw CatalogError.missing
        }
        return try Data(contentsOf: url, options: .mappedIfSafe)
    }

    private enum CatalogError: LocalizedError {
        case missing
        var errorDescription: String? { "تعذر فتح مكتبة التطبيقات المدمجة. أعد تثبيت آخر نسخة من TAIF PLUS." }
    }
}
