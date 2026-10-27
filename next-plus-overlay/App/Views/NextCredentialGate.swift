import SwiftUI

/// Reached only after a valid subscription. The catalog view is not mounted
/// until the selected local credential files have been opened and checked.
struct NextCredentialGate<Content: View>: View {
    @ObservedObject var certificates: CertificateStore
    @ObservedObject var profiles: ProfileStore
    @EnvironmentObject private var access: NextLicenseStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var deliveredVerifiedSelection: String?
    @State private var verifiedSelection: String?
    @State private var password = ""
    @State private var checking = false
    @State private var error: String?
    @State private var showCertificates = false
    @State private var showProfiles = false
    @State private var receivingCredential = false
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
            && ProcessInfo.processInfo.environment["TAIF_UI_SETUP"] != "1"
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
                                Image("TAIFPlusIcon").resizable().frame(width: 66, height: 66)
                                    .clipShape(RoundedRectangle(cornerRadius: 18))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("إعداد توقيعك").font(.title2.bold())
                                    Text("اشتراكك مفعّل. نجلب الشهادة المرتبطة بكودك، أو تضيف ملفاتك يدويًا.")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 8)
                        }
                        Section("شهادتك من المتجر") {
                            Button {
                                Task {
                                    await access.fetchAssignedCredential()
                                    if access.deliveredCredential == nil {
                                        error = access.message.isEmpty ? "المالك لم يربط شهادة بهذا الكود بعد." : access.message
                                    }
                                }
                            } label: {
                                HStack {
                                    Text(access.activating || receivingCredential ? "جاري جلب وفحص الشهادة…" : "جلب شهادتي من المتجر")
                                    Spacer()
                                    if access.activating || receivingCredential { ProgressView() }
                                    else { Image(systemName: "arrow.down.doc.fill") }
                                }
                            }.disabled(checking || receivingCredential || access.activating)
                            Text("إذا أضاف المالك ملفاتك في اللوحة، تصل تلقائيًا بعد إدخال كودك. نفحص الملفات قبل فتح المتجر.").font(.footnote).foregroundStyle(.secondary)
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
                            Text("نفحص فتح P12 وكلمة مروره وصلاحية الملفات وتوافق فريق التوقيع داخل جهازك. الملفات اليدوية تُفحص محليًا، والملفات المرتبطة بكودك تُجلب من خدمة المتجر عبر HTTPS.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }.taifFormSurface().navigationTitle("TAIF PLUS")
                }.navigationViewStyle(StackNavigationViewStyle())
            }
        }
        .sheet(isPresented: $showCertificates, onDismiss: automaticVerification) { CertificatesSheet() }
        .sheet(isPresented: $showProfiles, onDismiss: automaticVerification) { ProfilesSheet() }
        .task {
            if !previewEnabled && (certificates.selected == nil || profiles.selected == nil) {
                if access.deliveredCredential != nil { receiveDeliveredCredential() }
                else { await access.fetchAssignedCredential() }
            }
            automaticVerification()
        }
        .onReceive(access.$deliveredCredential) { credential in
            if credential != nil { receiveDeliveredCredential() }
        }
        .onChange(of: selection) { value in
            error = nil; password = ""
            if deliveredVerifiedSelection == value { verifiedSelection = value }
            else { deliveredVerifiedSelection = nil; verifiedSelection = nil; automaticVerification() }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active && !credentialsValid { automaticVerification() }
        }
        .onReceive(timer) { _ in
            if !credentialsValid { verifiedSelection = nil }
        }
    }

    private func receiveDeliveredCredential() {
        guard !checking, !receivingCredential, let delivery = access.deliveredCredential else { return }
        receivingCredential = true; checking = true; error = nil
        Task {
            defer { receivingCredential = false; checking = false; access.deliveredCredential = nil }
            guard delivery.p12.utf8.count <= 174_772, delivery.profile.utf8.count <= 349_536,
                  let p12 = Data(base64Encoded: delivery.p12), !p12.isEmpty, p12.count <= 131_072,
                  let profile = Data(base64Encoded: delivery.profile), !profile.isEmpty, profile.count <= 262_144,
                  delivery.password.utf8.count <= 512 else {
                error = "حزمة شهادة غير صالحة. اطلب من المالك إعادة رفع الملفات."; return
            }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let p12URL = folder.appendingPathComponent("taif-subscription.p12")
                let profileURL = folder.appendingPathComponent("taif-subscription.mobileprovision")
                try p12.write(to: p12URL, options: .completeFileProtection)
                try profile.write(to: profileURL, options: .completeFileProtection)
                let secret = delivery.password
                let issue: String? = await Task.detached(priority: .userInitiated) {
                    guard let cert = P12Inspector.inspect(url: p12URL, password: secret),
                          let provision = ProvisioningProfileInspector.inspect(data: profile) else {
                        return "ملفات الشهادة المرتبطة بكودك غير صالحة أو كلمة المرور غير صحيحة. اطلب من المالك مراجعتها."
                    }
                    if let start = cert.notBefore, start > Date() { return "شهادة المشترك لم يبدأ تاريخ صلاحيتها." }
                    return NextSigningPolicy.credentials(certificateExpiry: cert.notAfter,
                        profileExpiry: provision.expirationDate, certificateTeam: cert.teamID, profileTeam: provision.teamID)
                }.value
                if let issue { error = issue; return }
                if let cert = certificates.selected, let provision = profiles.selected,
                   (try? Data(contentsOf: certificates.fileURL(for: cert))) == p12,
                   (try? Data(contentsOf: profiles.fileURL(for: provision))) == profile {
                    certificates.cacheVerifiedPassword(secret, for: cert)
                } else {
                    let oldID = certificates.selectedID
                    let certificate: CertificateRecord
                    switch certificates.importCertificate(from: p12URL, password: secret, rememberPassword: true) {
                    case .success(let record): certificate = record
                    case .failure: error = "تعذر حفظ شهادة المشترك داخل الجهاز."; return
                    }
                    switch profiles.importProfile(from: profileURL) {
                    case .success: break
                    case .failure:
                        certificates.delete(certificate)
                        if let oldID { certificates.select(oldID) }
                        error = "تعذر حفظ ملف provisioning داخل الجهاز."; return
                    }
                }
                // Selection observers may reset state; perform the final existing gate check next turn.
                deliveredVerifiedSelection = selection
                verifiedSelection = selection; password = ""
            } catch { self.error = "تعذر حفظ ملفات الشهادة داخل الجهاز." }
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
