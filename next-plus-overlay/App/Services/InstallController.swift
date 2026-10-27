import Foundation
import SwiftUI
import UIKit

/// Keeps signed files independent of the temporary iOS installation handoff.
@MainActor
final class InstallController: ObservableObject {
    @Published var installServer: LocalInstallServer?
    @Published var installStatus = ""
    private var installTask: Task<Void, Never>?
    private var installGeneration = UUID()
    private var setupBackground: UIBackgroundTaskIdentifier = .invalid
    var onDelivered: (() -> Void)?

    func cancel() {
        installGeneration = UUID()
        installTask?.cancel(); installTask = nil
        installServer?.stop(); installServer = nil
        InstallKeepAlive.shared.stop()
        endSetupBackground()
        installStatus = "تم إيقاف طلب التثبيت. ملف IPA الموقّع يبقى محفوظًا."
    }

    func install(ipa: URL, bundleId: String, version: String, title: String = "TAIF PLUS") {
        cancel()
        let generation = UUID(); installGeneration = generation
        installStatus = "التحقق من ملف IPA وخدمة التثبيت…"
        // Continue the manifest handoff within iOS's finite background budget,
        // overlapping the signing assertion rather than leaving a suspension gap.
        setupBackground = UIApplication.shared.beginBackgroundTask(withName: "TAIF PLUS install manifest") { [weak self] in
            self?.cancel()
        }
        installTask = Task { [weak self] in
            guard let self else { return }
            do {
                guard FileManager.default.fileExists(atPath: ipa.path) else {
                    throw NextFailure("الملف الموقّع غير موجود. أعد توقيع التطبيق.")
                }
                let server = LocalInstallServer()
                _ = try await server.start(ipa: ipa, bundleId: bundleId, bundleVersion: version, title: title)
                guard installGeneration == generation, !Task.isCancelled else { server.stop(); return }
                installServer = server
                server.onIPADelivered = { [weak self] in
                    Task { @MainActor in
                        guard let self, self.installGeneration == generation else { return }
                        self.installStatus = "استلم iOS ملف التطبيق. راقب التثبيت على الشاشة الرئيسية؛ استلام الملف لا يؤكد قبول الشهادة."
                        self.onDelivered?()
                    }
                }
                var health = URLRequest(url: URL(string: server.payloadURL)!)
                health.httpMethod = "HEAD"; health.timeoutInterval = 10
                let (_, localResponse) = try await URLSession.shared.data(for: health)
                let expected = (try ipa.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0
                guard let local = localResponse as? HTTPURLResponse, local.statusCode == 200,
                      local.value(forHTTPHeaderField: "Content-Length") == String(expected) else {
                    throw NextFailure("فشل فحص نقل IPA داخل الجهاز. أعد المحاولة.")
                }
                var request = URLRequest(url: URL(string: server.remoteManifestURL)!)
                // This public plist endpoint rejects unrecognized client signatures.
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
                request.setValue("application/xml,text/xml,*/*", forHTTPHeaderField: "Accept")
                request.timeoutInterval = 20; request.cachePolicy = .reloadIgnoringLocalCacheData
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200,
                      let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let items = plist["items"] as? [[String: Any]],
                      let item = items.first,
                      let metadata = item["metadata"] as? [String: Any],
                      metadata["bundle-identifier"] as? String == bundleId,
                      let assets = item["assets"] as? [[String: Any]],
                      assets.contains(where: { $0["kind"] as? String == "software-package" && $0["url"] as? String == server.payloadURL }) else {
                    throw NextFailure("خدمة رابط التثبيت لم ترجع ملف manifest صالحًا. التوقيع محفوظ: صدّر IPA أو حاول لاحقًا.")
                }
                try Task.checkCancellation()
                guard installGeneration == generation else { return }
                guard let url = URL(string: server.itmsServicesURL) else { throw NextFailure("رابط التثبيت غير صالح.") }
                InstallKeepAlive.shared.start()
                installStatus = "أُرسل طلب التثبيت إلى iOS. وافق على النافذة إن ظهرت وأبقِ TAIF PLUS مفتوحًا أثناء النقل."
                let opened = await UIApplication.shared.open(url, options: [:])
                guard opened else { throw NextFailure("iOS لم يفتح طلب التثبيت. يمكنك تصدير IPA الموقّع.") }
                endSetupBackground()
                try await Task.sleep(nanoseconds: 10 * 60 * 1_000_000_000)
                guard installGeneration == generation else { return }
                installStatus = "انتهت مهلة نقل التثبيت. ملف IPA الموقّع محفوظ ويمكن إعادة الطلب."
                installServer?.stop(); installServer = nil; InstallKeepAlive.shared.stop()
                installTask = nil
            } catch {
                guard installGeneration == generation, !Task.isCancelled else { return }
                endSetupBackground()
                installStatus = "تعذر التثبيت: \(error.localizedDescription)\nالنسخة الموقّعة تبقى في المكتبة للتصدير أو إعادة المحاولة."
                installServer?.stop(); installServer = nil; InstallKeepAlive.shared.stop(); installTask = nil
            }
        }
    }

    private func endSetupBackground() {
        if setupBackground != .invalid {
            UIApplication.shared.endBackgroundTask(setupBackground)
            setupBackground = .invalid
        }
    }

    func openInstallPage() {
        guard let server = installServer, let url = URL(string: server.itmsServicesURL) else {
            installStatus = "اضغط تثبيت بجانب النسخة الموقّعة لبدء طلب جديد."
            return
        }
        UIApplication.shared.open(url)
    }
}

