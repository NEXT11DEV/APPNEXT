import SwiftUI
import UIKit

enum TaifPalette {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0xB00926, 0xFF5367)
    static let page = adaptive(0xFFFFFF, 0x0B0C10)
    static let card = adaptive(0xFFFFFF, 0x17181F)
    static let inset = adaptive(0xF7F7F9, 0x21222B)
    static let line = adaptive(0xE8E8ED, 0x30313B)
    static let ink = adaptive(0x18191D, 0xF5F5F8)
    static let ruby = Color(red: 0.67, green: 0.025, blue: 0.12)
    static let cherry = Color(red: 0.88, green: 0.10, blue: 0.20)
    static let hero = LinearGradient(colors: [Color(red: 0.20, green: 0.015, blue: 0.045), ruby, Color(red: 0.41, green: 0.025, blue: 0.095)], startPoint: .topTrailing, endPoint: .bottomLeading)
    static let action = LinearGradient(colors: [cherry, ruby], startPoint: .topLeading, endPoint: .bottomTrailing)
    static func scheme(_ raw: String) -> ColorScheme? {
        var mode = TaifAppearanceMode.restored(raw)
        #if DEBUG
        if let override = ProcessInfo.processInfo.environment["TAIF_UI_THEME"] { mode = .restored(override) }
        #endif
        switch mode { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
struct TaifAppearanceMenu: View {
    @AppStorage(TaifAppearanceMode.preferenceKey) private var mode = TaifAppearanceMode.system.rawValue
    var body: some View {
        Menu {
            Picker("المظهر", selection: $mode) {
                ForEach(TaifAppearanceMode.allCases) { value in Text(value.title).tag(value.rawValue) }
            }
        } label: {
            Image(systemName: "circle.lefthalf.filled").font(.system(size: 16, weight: .medium))
                .frame(width: 36, height: 36).background(TaifPalette.inset, in: Circle())
        }.accessibilityLabel("تغيير المظهر")
    }
}
extension View {
    @ViewBuilder func taifFormSurface() -> some View {
        if #available(iOS 16.0, *) { self.scrollContentBackground(.hidden).background(TaifPalette.page) }
        else { self.background(TaifPalette.page) }
    }
}
