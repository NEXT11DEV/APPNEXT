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
    private var iconData: Data?
    private var latestMessage = "جاري تجهيز التنزيل…"
    private var latestSubtitle = "TAIF PLUS"
    private var lastUnknownNotice: TimeInterval = -3

    func begin(title: String, iconURL: URL?, onExpiration: @escaping @MainActor @Sendable () -> Void) {
        end()
        active = true; allowed = false; bucket = -1; iconData = nil; latestMessage = "جاري تجهيز التنزيل…"
        latestSubtitle = "TAIF PLUS"; lastUnknownNotice = -3
        self.title = title
        notificationID = "taifplus.operation.\(UUID().uuidString)"
        let generation = notificationID
        backgroundID = UIApplication.shared.beginBackgroundTask(withName: "TAIF PLUS download and signing") { [weak self] in
            guard let self, self.notificationID == generation else { return }
            self.stage("انتهت مهلة العمل بالخلفية. افتح TAIF PLUS وأعد المحاولة.")
            onExpiration(); self.end()
        }
        Task {
            let bytes = await NextAppIconAsset.png(for: iconURL)
            guard active, notificationID == generation else { return }
            iconData = bytes
            publish()
        }
        let enabled = UserDefaults.standard.object(forKey: "taif.download-notifications") as? Bool ?? true
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
            if permission { publish() }
        }
    }

    func setLocalIcon(_ url: URL) {
        guard let image = UIImage(contentsOfFile: url.path) else { return }
        iconData = image.pngData()
    }

    func progress(_ value: NextTransferSnapshot) {
        latestMessage = value.notificationBody
        latestSubtitle = value.notificationSubtitle
        guard let percent = value.percent else {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastUnknownNotice >= 3 { lastUnknownNotice = now; publish() }
            return
        }
        let next = percent / 10
        guard next > bucket else { return }
        bucket = next
        publish()
    }

    func stage(_ message: String) {
        latestMessage = message
        latestSubtitle = "TAIF PLUS • التنزيل والتوقيع"
        publish()
    }

    private func publish() {
        guard active, allowed else { return }
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [notificationID])
        let content = UNMutableNotificationContent()
        content.title = title; content.subtitle = latestSubtitle
        content.body = String(latestMessage.prefix(240))
        content.threadIdentifier = notificationID
        if let iconData, iconData.count <= 1_024 * 1_024 {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("taif-notification-icons")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString + ".png")
            if (try? iconData.write(to: file)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "app-icon", url: file,
                   options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]) {
                content.attachments = [attachment]
            }
        }
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
