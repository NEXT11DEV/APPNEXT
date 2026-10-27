import SwiftUI
import UIKit

final class ForgeApplicationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.shortcutItems = []
        return true
    }
}

@main
struct ForgeSignMobileApp: App {
    @UIApplicationDelegateAdaptor(ForgeApplicationDelegate.self) private var appDelegate
    @StateObject private var certificates = CertificateStore()
    @StateObject private var profiles = ProfileStore()
    @AppStorage(TaifAppearanceMode.preferenceKey) private var appearanceMode = TaifAppearanceMode.system.rawValue
    @AppStorage("app.language") private var languageCode = AppLanguage.arabic.rawValue

    var body: some Scene {
        WindowGroup {
            NextAccessGate {
                NextCredentialGate(certificates: certificates, profiles: profiles) {
                    NextUnlockedWorkspace(certificates: certificates, profiles: profiles)
                }
            }
            .environment(\.appLanguage, .arabic)
            .environment(\.locale, Locale(identifier: "ar"))
            .environment(\.layoutDirection, .rightToLeft)
            .environmentObject(certificates)
            .environmentObject(profiles)
            .tint(TaifPalette.accent)
            .preferredColorScheme(TaifPalette.scheme(appearanceMode))
        }
    }
}


/// Expensive catalog state is created only after both entry gates have opened.
private struct NextUnlockedWorkspace: View {
    @ObservedObject var certificates: CertificateStore
    @ObservedObject var profiles: ProfileStore
    @StateObject private var history = HistoryStore()
    @StateObject private var installer = InstallController()
    @StateObject private var repositories = RepositoryStore()

    var body: some View {
        NextWorkspace(certificates: certificates, profiles: profiles, history: history,
                      installer: installer, repositories: repositories)
            .environmentObject(history)
            .environmentObject(installer)
            .environmentObject(repositories)
    }
}
