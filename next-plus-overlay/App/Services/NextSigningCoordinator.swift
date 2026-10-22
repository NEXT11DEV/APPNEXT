import Foundation

/// Owns the full operation independently of which tab is visible.
@MainActor
final class NextSigningCoordinator: ObservableObject {
    enum Phase: String { case idle, downloading, inspecting, signing, ready, failed }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double?
    @Published private(set) var title = ""
    @Published private(set) var detail = ""
    @Published var error: String?
    @Published var needsPassword = false
    @Published private(set) var signedURL: URL?
    @Published private(set) var signedBundle = ""
    @Published private(set) var signedVersion = ""
    @Published private(set) var log: [String] = []
    let certificates: CertificateStore
    let profiles: ProfileStore
    let history: HistoryStore
    let installer: InstallController
    private let staging = SigningService()
    private var task: Task<Void, Never>?
    private var waitingRequest: Request?

    enum Request { case repository(RepoApp), imported(URL) }
    var busy: Bool { [.downloading, .inspecting, .signing].contains(phase) }

    init(certificates: CertificateStore, profiles: ProfileStore, history: HistoryStore, installer: InstallController) {
        self.certificates = certificates; self.profiles = profiles
        self.history = history; self.installer = installer
    }

    func start(_ request: Request, password: String? = nil) {
        guard !busy else { return }
        error = nil
        if let message = NextSigningPolicy.credentials(certificateExpiry: certificates.selected?.notAfter,
            profileExpiry: profiles.selected?.notAfter, certificateTeam: certificates.selected?.teamID,
            profileTeam: profiles.selected?.teamID) { fail(message); return }
        guard let certificate = certificates.selected, let profile = profiles.selected else { return }
        guard let password = password ?? certificates.savedPassword(for: certificate) else {
            waitingRequest = request; needsPassword = true; return
        }
        // An empty string is a valid P12 password and must reach OpenSSL.
        signedURL = nil; progress = nil; log = []
        let certificateURL = certificates.fileURL(for: certificate)
        let profileURL = profiles.fileURL(for: profile)
        let work = staging.tempDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = history.signedDir.appendingPathComponent("next-\(UUID().uuidString).ipa")
        let appName: String
        switch request { case .repository(let app): appName = app.name; case .imported(let url): appName = url.deletingPathExtension().lastPathComponent }
        title = appName
        phase = .inspecting; detail = "فحص ملفات التوقيع…"
        task = Task {
            defer { task = nil; try? FileManager.default.removeItem(at: work) }
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
                guard let info = await Task.detached(priority: .userInitiated, operation: {
                    P12Inspector.inspect(url: certificateURL, password: password)
                }).value else { throw NextFailure("تعذر فتح شهادة P12. تحقق من كلمة مرورها، حتى إذا كانت فارغة.") }
                if let issue = NextSigningPolicy.credentials(certificateExpiry: info.notAfter,
                    profileExpiry: profile.notAfter, certificateTeam: info.teamID, profileTeam: profile.teamID) { throw NextFailure(issue) }
                let ipa: URL
                switch request {
                case .repository(let app):
                    guard let url = app.downloadURL, ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
                        throw NextFailure("هذا التطبيق لا يحتوي رابط IPA صالحًا.")
                    }
                    phase = .downloading; detail = "جاري تنزيل التطبيق…"; record("بدء تنزيل IPA")
                    let downloader = NextIPADownload()
                    ipa = try await downloader.run(url: url, destination: work.appendingPathComponent("input.ipa")) { [weak self] value in
                        Task { @MainActor in self?.progress = value }
                    }
                case .imported(let source):
                    let scoped = source.startAccessingSecurityScopedResource()
                    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
                    let target = work.appendingPathComponent("input.ipa")
                    try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: source, to: target) }.value
                    ipa = target
                }
                try Task.checkCancellation()
                phase = .inspecting; progress = nil; detail = "فحص IPA وصلاحياته…"; record("اكتمل تنزيل/استيراد الملف؛ بدء فحص IPA")
                let inspection = try await Task.detached(priority: .userInitiated) {
                    try IPAPreflightService.inspect(ipa: ipa, temporaryDirectory: work).get()
                }.value
                guard inspection.encryptedExecutableCount == 0 else { throw NextFailure("التطبيق مشفّر من App Store؛ إعادة التوقيع وحدها لا تكفي لتثبيته.") }
                guard NextSigningPolicy.allows(bundleID: inspection.bundleIdentifier, applicationIdentifier: profile.applicationIdentifier) else {
                    throw NextFailure("ملف provisioning لا يسمح بمعرّف التطبيق \(inspection.bundleIdentifier). تحتاج ملفًا يسمح بهذا التطبيق.")
                }
                try Task.checkCancellation()
                phase = .signing; detail = "توقيع التطبيق داخل الآيفون…"; record("بدء محرك zsign")
                let result = await Task.detached(priority: .userInitiated) {
                    SigningService.sign(ipa: ipa, p12: certificateURL, password: password, profile: profileURL,
                        bundleId: "", displayName: "", shortVersion: "", icon: nil, output: output,
                        tempDir: work, removeExtensions: false, enableDocuments: false)
                }.value
                guard result.ok else { throw NextFailure(result.message) }
                guard FileManager.default.fileExists(atPath: output.path),
                      ((try? output.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0 else {
                    throw NextFailure("محرك التوقيع لم ينتج ملف IPA صالحًا.")
                }
                try Task.checkCancellation()
                signedURL = output; signedBundle = result.signedBundleId; signedVersion = result.signedVersion
                title = inspection.appName
                history.append(inputName: inspection.appName, outputName: output.lastPathComponent,
                               bundleId: result.signedBundleId, version: result.signedVersion, certificateCN: certificate.commonName)
                phase = .ready; detail = "تم التوقيع. اضغط «تثبيت النسخة الموقّعة» لإرسالها إلى iOS."
                record("نجح التوقيع؛ النسخة محفوظة في المكتبة")
            } catch is CancellationError {
                try? FileManager.default.removeItem(at: output)
                phase = .idle; detail = "تم إلغاء العملية."; record("إلغاء العملية")
            } catch {
                try? FileManager.default.removeItem(at: output)
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
    private func record(_ value: String) { log.append(value) }
    private func fail(_ message: String) { phase = .failed; detail = message; error = message; record(message) }
}

struct NextFailure: LocalizedError, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
