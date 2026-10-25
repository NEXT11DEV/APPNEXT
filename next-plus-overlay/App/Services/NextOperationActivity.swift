import UIKit
import UserNotifications

/// Real progress notifications plus the finite background time iOS grants.
/// It never promises unrestricted signing while the app is suspended.
@MainActor
final class NextOperationActivity {
    private var backgroundID: UIBackgroundTaskIdentifier = .invalid
    private var notificationID = UUID().uuidString
    private var title = ""
    private var active = false
    private var allowed = false
    private var bucket = -1

    func begin(title: String, onExpiration: @escaping @MainActor @Sendable () -> Void) {
        end()
        active = true; allowed = false; bucket = -1
        self.title = title
        notificationID = "idkplus.operation.\(UUID().uuidString)"
        let generation = notificationID
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "idk plus download and signing") { [weak self] in
            guard let self, self.notificationID == generation else { return }
            self.stage("انتهت مهلة العمل بالخلفية. افتح idk plus وأعد المحاولة.")
            onExpiration(); self.end()
        }
        let enabled = UserDefaults.standard.object(forKey: "idk.download-notifications") as? Bool ?? true
        guard enabled else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            var permission = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            if settings.authorizationStatus == .notDetermined {
                permission = (try? await center.requestAuthorization(options: [.alert])) ?? false
            }
            guard active, notificationID == generation else { return }
            allowed = permission
        }
    }

    func progress(_ value: Double?) {
        guard let value, value.isFinite else { return }
        let percent = min(100, max(0, Int(value * 100)))
        let next = percent / 20
        guard next > bucket else { return }
        bucket = next
        stage("جاري التنزيل: \(percent)٪")
    }

    func stage(_ message: String) {
        guard active, allowed else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        let content = UNMutableNotificationContent()
        content.title = title; content.subtitle = "idk plus"
        content.body = String(message.prefix(240))
        content.threadIdentifier = notificationID
        center.add(UNNotificationRequest(identifier: notificationID, content: content, trigger: nil), withCompletionHandler: nil)
    }

    func end() {
        active = false
        if backgroundID != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundID)
            backgroundID = .invalid
        }
    }
}
