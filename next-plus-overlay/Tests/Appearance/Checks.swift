import Foundation
@main struct AppearanceChecks {
    static func main() {
        precondition(TaifAppearanceMode.restored("light") == .light)
        precondition(TaifAppearanceMode.restored("dark") == .dark)
        precondition(TaifAppearanceMode.restored("system") == .system)
        precondition(TaifAppearanceMode.restored("invalid") == .system)
        let domain = "taif-appearance-tests-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: domain)!
        defer { preferences.removePersistentDomain(forName: domain) }
        preferences.set("dark", forKey: TaifAppearanceMode.preferenceKey)
        precondition(TaifAppearanceMode.restored(preferences.string(forKey: TaifAppearanceMode.preferenceKey)!) == .dark)
        preferences.set("light", forKey: TaifAppearanceMode.preferenceKey)
        precondition(preferences.string(forKey: TaifAppearanceMode.preferenceKey) == "light")
        print("PASS: light/dark/system preferences restore correctly and persist across reads")
    }
}
