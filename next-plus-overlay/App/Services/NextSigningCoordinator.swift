import Foundation

/// Owns the full operation independently of which tab is visible.
@MainActor
final class NextSigningCoordinator: ObservableObject {
    enum Phase: String { case idle, downloading, inspecting, signing, ready, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double?
    @Published private(set) var transfer: NextTransferSnapshot?
    @Published private(set) var iconURL: URL?
    @Published private(set) var title = ""
    @Published private(set) var detail = ""
    @Published var error: String?
    @Published var needsPassword = false
    @Published private(set) var signedURL: URL?
    @Published private(set) var signedBundle = ""
    @Published private(set) var signedVersion = ""
    @Published private(set) var log: [String] = []
    @Published private(set) var signingNotice: String?
    let certificates: CertificateStore
    let profiles: ProfileStore
    let history: HistoryStore
    let installer: InstallController
    private let staging = SigningService()
    private let activity = NextOperationActivity()
    private var task: Task<Void, Never>?
    private var waitingRequest: Request?
    private var operationID = UUID()

    enum Request { case repository(RepoApp), repositoryCopy(RepoApp), imported(URL), importedCopy(URL) }
    var busy: Bool { [.downloading, .inspecting, .signing].contains(phase) }

    init(certificates: CertificateStore, profiles: ProfileStore, history: HistoryStore, installer: InstallController) {
        self.certificates = certificates; self.profiles = profiles
        self.history = history; self.installer = installer
    }

    func start(_ request: Request, password: String? = nil) {
        guard !busy else { return }
        error = nil; signingNotice = nil
        if let message = NextSigningPolicy.credentials(certificateExpiry: certificates.selected?.notAfter,
            profileExpiry: profiles.selected?.notAfter, certificateTeam: certificates.selected?.teamID,
            profileTeam: profiles.selected?.teamID) { fail(message); return }
        guard let certificate = certificates.selected, let profile = profiles.selected else { return }
        guard let password = password ?? certificates.savedPassword(for: certificate) else {
            waitingRequest = request; needsPassword = true; return
        }
        // An empty string is a valid P12 password and must reach OpenSSL.
        signedURL = nil; progress = nil; transfer = nil; iconURL = nil; log = []
        let certificateURL = certificates.fileURL(for: certificate)
        let profileURL = profiles.fileURL(for: profile)
        let work = staging.tempDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = history.signedDir.appendingPathComponent("next-\(UUID().uuidString).ipa")
        let appName: String
        switch request { case .repository(let app), .repositoryCopy(let app): appName = app.name; case .imported(let url), .importedCopy(let url): appName = url.deletingPathExtension().lastPathComponent }
        switch request {
        case .repository(let app), .repositoryCopy(let app): iconURL = app.iconURL
        default: break
        }
        let currentOperation = UUID(); operationID = currentOperation
        title = appName
        phase = .inspecting; detail = "فحص ملفات التوقيع…"
        task = Task {
            let operationStarted = ProcessInfo.processInfo.systemUptime
            activity.begin(title: appName, iconURL: iconURL) { [weak self] in self?.cancel() }
            defer { activity.end(); task = nil; try? FileManager.default.removeItem(at: work) }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                guard let info = await Task.detached(priority: .userInitiated, operation: {
                    P12Inspector.inspect(url: certificateURL, password: password)
                }).value else { throw NextFailure("تعذر فتح شهادة P12. تحقق من كلمة مرورها، حتى إذا كانت فارغة.") }
                if let issue = NextSigningPolicy.credentials(certificateExpiry: info.notAfter,
                    profileExpiry: profile.notAfter, certificateTeam: info.teamID, profileTeam: profile.teamID) { throw NextFailure(issue) }
                recordDuration("فحص الشهادة", since: operationStarted)
                let ipa: URL
                switch request {
                case .repository(let app), .repositoryCopy(let app):
                    guard let url = app.downloadURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                        throw NextFailure("هذا التطبيق لا يحتوي رابط IPA صالحًا.")
                    }
                    phase = .downloading; detail = "جاري تنزيل التطبيق…"; record("بدء تنزيل IPA")
                    let downloadStarted = ProcessInfo.processInfo.systemUptime
                    let downloader = NextIPADownload()
                    ipa = try await downloader.run(url: url, destination: work.appendingPathComponent("input.ipa")) { [weak self] value in
                        Task { @MainActor in
                            guard let self, self.operationID == currentOperation, self.phase == .downloading else { return }
                            self.transfer = value
                            self.progress = value.fraction
                            self.activity.progress(value)
                        }
                    }
                    let elapsed = max(ProcessInfo.processInfo.systemUptime - downloadStarted, 0.001)
                    let bytes = Int64((try? ipa.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    recordDuration("التنزيل", since: downloadStarted)
                    record("حجم IPA: \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))؛ متوسط التنزيل: \(ByteCountFormatter.string(fromByteCount: Int64(Double(bytes) / elapsed), countStyle: .file))/ثانية")
                case .imported(let source), .importedCopy(let source):
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    let target = work.appendingPathComponent("input.ipa")
                    try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: source, to: target) }.value
                    ipa = target
                }
                try Task.checkCancellation()
                phase = .inspecting; progress = nil; detail = "فحص IPA وصلاحياته…"; record("اكتمل تنزيل/استيراد الملف؛ بدء فحص IPA")
                activity.stage("اكتمل التنزيل؛ جاري فحص التطبيق…")
                let inspectionStarted = ProcessInfo.processInfo.systemUptime
                let inspection = try await Task.detached(priority: .userInitiated) {
                    try IPAPreflightService.inspect(ipa: ipa, temporaryDirectory: work, retainForSigning: true).get()
                }.value
                recordDuration("فحص IPA", since: inspectionStarted)
                if let localIcon = inspection.iconURL {
                    iconURL = localIcon
                    activity.setLocalIcon(localIcon)
                }
                guard inspection.encryptedExecutableCount == 0 else { throw NextFailure("التطبيق مشفّر من App Store؛ إعادة التوقيع وحدها لا تكفي لتثبيته.") }
                guard inspection.preparedFolder != nil else { throw NextFailure("تعذر تجهيز ملفات التطبيق للتوقيع.") }
                record("فُكّ IPA مرة واحدة؛ التوقيع يستخدم نفس الملفات المفحوصة")
                let targetIdentifier: String
                let targetName: String
                switch request {
                case .repositoryCopy, .importedCopy:
                    guard let duplicate = NextSigningPolicy.duplicateIdentifier(inspection.bundleIdentifier,
                        existing: Set(history.records.map(\.bundleId))) else {
                        throw NextFailure("تعذر إنشاء معرّف نسخة جديد بحرفين. جرّب تطبيقًا آخر أو راجع النسخ السابقة.")
                    }
                    targetIdentifier = duplicate
                    targetName = inspection.appName + " " + String(duplicate.suffix(2))
                    record("نسخة إضافية: \(inspection.bundleIdentifier) ← \(duplicate)")
                default:
                    targetIdentifier = ""; targetName = ""
                }
                if let notice = NextSigningPolicy.profileNotice(bundleID: targetIdentifier.isEmpty ? inspection.bundleIdentifier : targetIdentifier,
                    applicationIdentifier: profile.applicationIdentifier) {
                    signingNotice = notice
                    record(notice)
                }
                try Task.checkCancellation()
                phase = .signing; detail = "توقيع التطبيق داخل الآيفون…"; record("بدء محرك zsign")
                activity.stage("جاري توقيع التطبيق داخل الآيفون…")
                let signingStarted = ProcessInfo.processInfo.systemUptime
                let result = await Task.detached(priority: .userInitiated) {
                    SigningService.sign(ipa: ipa, p12: certificateURL, password: password, profile: profileURL,
                        bundleId: targetIdentifier, displayName: targetName, shortVersion: "", icon: nil, output: output,
                        tempDir: work, removeExtensions: false, enableDocuments: false, preparedFolder: inspection.preparedFolder)
                }.value
                recordDuration("التوقيع وتجهيز IPA", since: signingStarted)
                guard result.ok else { throw NextFailure(result.message) }
                guard FileManager.default.fileExists(atPath: output.path),
                      ((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
                    throw NextFailure("محرك التوقيع لم ينتج ملف IPA صالحًا.")
                }
                try Task.checkCancellation()
                signedURL = output; signedBundle = result.signedBundleId; signedVersion = result.signedVersion
                title = targetName.isEmpty ? inspection.appName : targetName
                history.append(inputName: title, outputName: output.lastPathComponent,
                               bundleId: result.signedBundleId, version: result.signedVersion, certificateCN: certificate.commonName)
                phase = .ready; detail = "تم التوقيع. جاري فتح طلب التثبيت؛ وافق على نافذة iOS عند ظهورها."
                record("نجح التوقيع؛ النسخة محفوظة في المكتبة")
                recordDuration("الإجمالي قبل طلب التثبيت", since: operationStarted)
                activity.stage("اكتمل التوقيع. وافق على نافذة التثبيت، أو افتح TAIF PLUS لإعادة طلبها.")
                installSigned()
            } catch is CancellationError {
                activity.stage("تم إلغاء العملية.")
                try? FileManager.default.removeItem(at: output)
                phase = .idle; detail = "تم إلغاء العملية."; record("إلغاء العملية")
            } catch {
                try? FileManager.default.removeItem(at: output)
                activity.stage("تعذر إكمال العملية: " + error.localizedDescription)
                fail(error.localizedDescription)
            }
        }
    }

    func providePassword(_ password: String) {
        needsPassword = false
        if let request = waitingRequest { waitingRequest = nil; start(request, password: password) }
    }

    func cancelPassword() { needsPassword = false; waitingRequest = nil }
    func cancel() { task?.cancel() }
    func installSigned() {
        guard let signedURL else { return }
        installer.install(ipa: signedURL, bundleId: signedBundle, version: signedVersion, title: title)
    }
    private func recordDuration(_ label: String, since start: TimeInterval) {
        record(String(format: "%@: %.2f ثانية", label, ProcessInfo.processInfo.systemUptime - start))
    }
    private func record(_ value: String) { log.append(value) }
    private func fail(_ message: String) { phase = .failed; detail = message; error = message; record(message) }
}

struct NextFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}


