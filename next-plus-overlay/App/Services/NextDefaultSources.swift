import Foundation

/// Adds the owner's catalog to both new and existing installations without
/// replacing user-added repositories or duplicating an already-added URL.
enum NextDefaultSources {
    static let ownerURL = URL(string: "https://raw.githubusercontent.com/NEXT11DEV/NEXT-SOURCE/main/NEXTDEV-ESign.json")!

    @discardableResult
    static func seed(in repositories: inout [Repository]) -> Bool {
        guard !repositories.contains(where: { $0.url == ownerURL }) else { return false }
        repositories.append(Repository(url: ownerURL, name: "NEXT PlUS"))
        return true
    }
}
