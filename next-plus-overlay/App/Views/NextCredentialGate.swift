import SwiftUI

/// Reached only after a valid subscription. The catalog view is not mounted
/// until the selected local credential files have been opened and checked.
struct NextCredentialGate<Content: View>: View {
    @ObservedObject var certificates: CertificateStore
    @ObservedObject var profiles: ProfileStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var verifiedSelection: String?
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?
    @State private var showCertificates = false
    @State private var showProfiles = false
    private let content: Content
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(certificates: CertificateStore, profiles: ProfileStore, @ViewBuilder content: () -> Content) {
        self.certificates = certificates; self.profiles = profiles; self.content = content()
    }

    private var selection: String {
        "\(certificates.selectedID?.uuidString ?? "none")|\(profiles.selectedID?.uuidString ?? "none")"
    }

    private var previewEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NEXT_UI_PREVIEW"] == "1"
            && ProcessInfo.processInfo.environment["IDK_UI_SETUP"] != "1"
        #else
        return false
        #endif
    }

    private var credentialsValid: Bool {
        guard verifiedSelection == selection,
              let certificate = certificates.selected, let profile = profiles.selected,
              FileManager.default.fileExists(atPath: certificates.fileURL(for: certificate).path),
              FileManager.default.fileExists(atPath: profiles.fileURL(for: profile).path) else { return false }
        return NextSigningPolicy.credentials(certificateExpiry: certificate.notAfter,
            profileExpiry: profile.notAfter, certificateTeam: certificate.teamID, profileTeam: profile.teamID) == nil
    }

    var body: some View {
        Group {
            if previewEnabled || credentialsValid {
                content
            } else {
                NavigationView {
                    Form {
                        Section {
                            HStack(spacing: 14) {
                                Image("IDKPlusIcon").resizable().frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("إعداد توقيعك").font(.title2.bold())
                                    Text("اشتراكك مفعّل. أضف ملفات التوقيع حتى تفتح المتجر.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }
                        Section("١ · شهادة P12") {
                            Button { showCertificates = true } label: {
                                Label(certificates.selected?.displayName ?? "إضافة شهادة P12", systemImage: "key.fill")
                            }.disabled(checking)
                            if let certificate = certificates.selected,
                               certificates.savedPassword(for: certificate) == nil {
                                SecureField("كلمة مرور الشهادة، أو اتركها فارغة", text: $password)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                            }
                        }
                        Section("٢ · ملف provisioning") {
                            Button { showProfiles = true } label: {
                                Label(profiles.selected?.displayName ?? "إضافة ملف mobileprovision", systemImage: "doc.badge.gearshape.fill")
                            }.disabled(checking)
                        }
                        Section {
                            Button { verify() } label: {
                                HStack {
                                    Text(checking ? "جاري فحص الملفات…" : "تحقق وافتح المتجر")
                                    Spacer()
                                    if checking { ProgressView() }
                                    else { Image(systemName: "arrow.left.circle.fill") }
                                }
                            }.disabled(checking || certificates.selected == nil || profiles.selected == nil)
                            if let error { Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled) }
                            Text("نفحص فتح P12 وكلمة مروره وصلاحية الملفات وتوافق فريق التوقيع داخل جهازك. ملفاتك ما تنرفع لسيرفر.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.navigationTitle("idk plus")
                }.navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .sheet(isPresented: $showCertificates, onDismiss: automaticVerification) { CertificatesSheet() }
        .sheet(isPresented: $showProfiles, onDismiss: automaticVerification) { ProfilesSheet() }
        .task { automaticVerification() }
        .onChange(of: selection) { _ in verifiedSelection = nil; error = nil; password = "" }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !credentialsValid { automaticVerification() }
        }
        .onReceive(timer) { _ in
            if !credentialsValid { verifiedSelection = nil }
        }
    }

    private func automaticVerification() {
        guard !previewEnabled, !checking, let certificate = certificates.selected,
              profiles.selected != nil, certificates.savedPassword(for: certificate) != nil else { return }
        verify()
    }

    private func verify() {
        guard !checking, let certificate = certificates.selected, let profile = profiles.selected else { return }
        let expectedSelection = selection
        let certificateURL = certificates.fileURL(for: certificate)
        let profileURL = profiles.fileURL(for: profile)
        let secret = certificates.savedPassword(for: certificate) ?? password
        checking = true; error = nil; verifiedSelection = nil
        Task {
            let issue: String? = await Task.detached(priority: .userInitiated) {
                guard let info = P12Inspector.inspect(url: certificateURL, password: secret) else {
                    return "تعذر فتح P12. تحقق من الشهادة وكلمة المرور."
                }
                guard let bytes = try? Data(contentsOf: profileURL),
                      let provisioning = ProvisioningProfileInspector.inspect(data: bytes) else {
                    return "تعذر قراءة ملف provisioning. اختَر ملفًا صالحًا."
                }
                if let notBefore = info.notBefore, notBefore > Date() {
                    return "شهادة P12 لم يبدأ تاريخ صلاحيتها بعد."
                }
                return NextSigningPolicy.credentials(certificateExpiry: info.notAfter,
                    profileExpiry: provisioning.expirationDate,
                    certificateTeam: info.teamID, profileTeam: provisioning.teamID)
            }.value
            checking = false
            guard selection == expectedSelection else { return }
            if let issue { error = issue }
            else {
                certificates.cacheVerifiedPassword(secret, for: certificate)
                verifiedSelection = expectedSelection; password = ""
            }
        }
    }
}
