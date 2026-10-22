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
    @StateObject private var history = HistoryStore()
    @StateObject private var installer = InstallController()
    @StateObject private var repositories = RepositoryStore()
    @AppStorage("app.language") private var languageCode = AppLanguage.arabic.rawValue

    var body: some Scene {
        WindowGroup {
            NextAccessGate {
                NextWorkspace(certificates: certificates, profiles: profiles, history: history,
                              installer: installer, repositories: repositories)
            }
            .environment(\.appLanguage, .arabic)
            .environment(\.locale, Locale(identifier: "ar"))
            .environment(\.layoutDirection, .rightToLeft)
            .environmentObject(certificates)
            .environmentObject(profiles)
            .environmentObject(history)
            .environmentObject(installer)
            .environmentObject(repositories)
        }
    }
}
