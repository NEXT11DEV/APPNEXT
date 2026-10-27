import Foundation

enum TaifAppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self { case .system: return "تلقائي"; case .light: return "فاتح"; case .dark: return "داكن" }
    }
    static func restored(_ value: String) -> Self { Self(rawValue: value) ?? .system }
    static let preferenceKey = "taif.appearance"
}
