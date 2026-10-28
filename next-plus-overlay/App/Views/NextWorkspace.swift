import SwiftUI
import UniformTypeIdentifiers

private typealias NextStyle = TaifPalette

struct NextWorkspace: View {
    @ObservedObject var certificates: CertificateStore
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var installer: InstallController
    @ObservedObject var repositories: RepositoryStore
    @StateObject private var signing: NextSigningCoordinator
    @AppStorage(TaifAppearanceMode.preferenceKey) private var appearanceMode = TaifAppearanceMode.system.rawValue
    @AppStorage("taif.download-notifications") private var downloadNotifications = true
    @State private var tab = 0
    @State private var query = ""
    @State private var selectedApp: RepoApp?
    @State private var showSources = false
    @State private var showCertificates = false
    @State private var showProfiles = false
    @State private var showImporter = false
    @State private var password = ""
    @State private var category = "الكل"
    @State private var refreshed = false
    @State private var showReadyBanner = true

    init(certificates: CertificateStore, profiles: ProfileStore, history: HistoryStore,
         installer: InstallController, repositories: RepositoryStore) {
        #if DEBUG
        _tab = State(initialValue: Int(ProcessInfo.processInfo.environment["NEXT_UI_TAB"] ?? "0") ?? 0)
        #endif
        self.certificates = certificates; self.profiles = profiles; self.history = history
        self.installer = installer; self.repositories = repositories
        _signing = StateObject(wrappedValue: NextSigningCoordinator(certificates: certificates,
            profiles: profiles, history: history, installer: installer))
    }

    @State private var allApps: [RepoApp] = []
    @State private var apps: [RepoApp] = []
    @State private var visibleLimit = NextCatalogIndex.pageSize
    @State private var hasMoreApps = false

    private func resetPage() {
        visibleLimit = NextCatalogIndex.pageSize
        updatePage()
    }

    private func updatePage() {
        let page = NextCatalogIndex.page(allApps, query: query, category: category, limit: visibleLimit)
        apps = page.apps
        hasMoreApps = page.hasMore
    }

    private func showMore() {
        guard hasMoreApps else { return }
        visibleLimit += NextCatalogIndex.pageSize
        updatePage()
    }

    private func rebuildCatalog(repositories: [Repository], catalog: [UUID: RepoSource]) {
        let index = NextCatalogIndex.flatten(repositories: repositories, catalog: catalog)
        allApps = index
        resetPage()
    }

    var body: some View {
        workspacePages
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomDock }
            .safeAreaInset(edge: .top, spacing: 0) { transferBanner }
            .background(NextStyle.page.ignoresSafeArea())
        .onReceive(repositories.$catalog) { catalog in
            rebuildCatalog(repositories: repositories.repositories, catalog: catalog)
        }
        .onReceive(repositories.$repositories) { repositories in
            rebuildCatalog(repositories: repositories, catalog: self.repositories.catalog)
        }
        .onChange(of: query) { _ in resetPage() }
        .onChange(of: category) { _ in resetPage() }
        .onChange(of: signing.phase) { phase in
            if phase != .idle && phase != .ready { showReadyBanner = true }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(NextStyle.accent)
        
        .sheet(item: $selectedApp) { app in
            NextAppDetails(app: app, busy: signing.busy) { selected, copy in
                signing.start(copy ? .repositoryCopy(selected) : .repository(selected))
            }
        }
        .sheet(isPresented: $showSources) { SourcesView() }
        .sheet(isPresented: $showCertificates) { CertificatesSheet() }
        .sheet(isPresented: $showProfiles) { ProfilesSheet() }
        .sheet(isPresented: $showImporter) {
            ForgeDocumentPicker { urls in
                showImporter = false
                guard let url = urls.first else { return }
                signing.start(.imported(url)); tab = 1
            } onCancel: { showImporter = false }
        }
        .sheet(isPresented: $signing.needsPassword, onDismiss: { password = "" }) {
            NavigationView {
                Form {
                    Section {
                        Text("أدخل كلمة مرور شهادة P12 المختارة. اتركها فارغة إذا الشهادة بدون كلمة مرور.")
                        SecureField("كلمة مرور P12", text: $password)
                    }
                    Button("متابعة التوقيع") { signing.providePassword(password); password = "" }
                }
                .navigationTitle("كلمة مرور الشهادة")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { signing.cancelPassword() } } }
            }.navigationViewStyle(StackNavigationViewStyle())
        }
        .alert("تعذر إكمال العملية", isPresented: Binding(get: { signing.error != nil }, set: { if !$0 { signing.error = nil } })) {
            Button("إعداد الشهادة") { tab = 2 }
            Button("حسنًا", role: .cancel) { signing.error = nil }
        } message: { Text(signing.error ?? "") }
    }

    private var workspacePages: some View {
        ZStack {
            store.opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
            library.opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
            settings.opacity(tab == 2 ? 1 : 0).allowsHitTesting(tab == 2).accessibilityHidden(tab != 2)
        }
    }

    private var bottomDock: some View {
        HStack(spacing: 0) {
            dockButton("اكتشف", symbol: "safari", value: 0)
            dockButton("التنزيلات", symbol: "arrow.down.circle", value: 1)
            Button { showImporter = true } label: {
                Image(systemName: "plus").font(.system(size: 22, weight: .medium)).frame(width: 46, height: 46)
                    .foregroundColor(.white).background(TaifPalette.ruby, in: Circle())
            }.accessibilityLabel("استيراد IPA")
            dockButton("حسابي", symbol: "person.crop.circle", value: 2)
        }
        .padding(.horizontal, 18).padding(.top, 3).padding(.bottom, 4)
        .background(NextStyle.page)
        .overlay(alignment: .top) { Rectangle().fill(TaifPalette.line).frame(height: 1) }
    }

    private func dockButton(_ title: String, symbol: String, value: Int) -> some View {
        Button { tab = value } label: {
            VStack(spacing: 6) {
                Capsule().fill(tab == value ? NextStyle.accent : .clear).frame(width: 22, height: 3)
                HStack(spacing: 7) {
                    Image(systemName: symbol).font(.system(size: 18, weight: .medium))
                    Text(title).font(.system(size: 11, weight: .bold))
                }.padding(.vertical, 10)
            }
            .foregroundStyle(tab == value ? NextStyle.accent : Color.secondary)
            .frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityAddTraits(tab == value ? .isSelected : [])
    }

    @ViewBuilder private var transferBanner: some View {
        if signing.busy || (signing.phase == .ready && showReadyBanner) {
            NextTransferBanner(title: signing.title, iconURL: signing.iconURL,
                fraction: signing.phase == .downloading ? signing.progress : nil,
                detail: signing.phase == .downloading ? ((signing.transfer?.percent.map { "\($0)٪ · " } ?? "") + (signing.transfer?.bytesText ?? "جاري الاتصال…")) : signing.detail,
                ready: signing.phase == .ready,
                onOpen: { tab = 1 }, onClose: {
                    if signing.busy { signing.cancel() } else { showReadyBanner = false }
                })
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
        }
        else {
        #if DEBUG
        if ProcessInfo.processInfo.environment["TAIF_UI_TRANSFER"] == "1" {
            NextTransferBanner(title: "معاينة التنزيل · Example.ipa", iconURL: nil, fraction: 0.42,
                detail: "13.4 MB / 32 MB", ready: false, onOpen: {}, onClose: {})
                .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
        }
        #endif
        }
    }

    private var store: some View {
        TaifDiscovery(apps: apps, total: allApps.count, more: hasMoreApps, busy: signing.busy,
            query: $query, category: $category,
            details: { selectedApp = $0 }, install: { signing.start(.repository($0)) },
            loadMore: { showMore() }, importIPA: { showImporter = true }, settings: { tab = 2 })
        .refreshable { await refresh() }
        .task {
            guard !refreshed else { return }; refreshed = true
            while !repositories.catalogCacheLoaded { try? await Task.sleep(nanoseconds: 20_000_000) }
            await refresh()
            #if DEBUG
            if ProcessInfo.processInfo.environment["TAIF_UI_DETAILS"] == "1", let first = allApps.first { selectedApp = first }
            #endif
        }
    }

    private var library: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Button { showImporter = true } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "plus.app.fill").font(.largeTitle)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("استيراد ملف IPA").font(.headline)
                                Text("من ملفات جهازك، ثم توقيعه بشهادتك").font(.caption)
                            }
                            Spacer(); Image(systemName: "plus")
                        }.foregroundStyle(.white).padding(22)
                            .background(LinearGradient(colors: [NextStyle.accent.opacity(0.8), NextStyle.accent], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
                    }.buttonStyle(.plain).disabled(signing.busy)
                    if signing.phase != .idle { operationCard }
                    if !installer.installStatus.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("طلب التثبيت").font(.headline)
                            Text(installer.installStatus).font(.subheadline).textSelection(.enabled)
                            HStack {
                                Button("فتح طلب التثبيت مرة ثانية") { installer.openInstallPage() }.buttonStyle(.bordered)
                                Button("إيقاف الطلب") { installer.cancel() }.buttonStyle(.bordered)
                            }
                        }.padding(18).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                    Text("التطبيقات الموقّعة").font(.title3.bold())
                    if history.records.isEmpty {
                        Text("النسخ التي توقّعها تظهر هنا وتبقى محفوظة لإعادة التثبيت أو المشاركة.")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                    }
                    ForEach(history.records) { record in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                Image(systemName: "app.badge.checkmark").font(.title).foregroundStyle(NextStyle.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.inputName).font(.headline).lineLimit(2)
                                    Text(record.bundleId).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            HStack {
                                Button("تثبيت") { installer.install(ipa: history.outputURL(for: record), bundleId: record.bundleId, version: record.version, title: record.inputName) }
                                    .buttonStyle(.borderedProminent).disabled(!history.fileExists(for: record) || signing.busy)
                                if history.fileExists(for: record) {
                                    Button("تكرار") { signing.start(.importedCopy(history.outputURL(for: record))) }
                                        .buttonStyle(.bordered).disabled(signing.busy)
                                }
                                if history.fileExists(for: record) { NextShareButton(item: history.outputURL(for: record)) { Label("مشاركة IPA", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) }
                            }
                        }.padding(18).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding(20).padding(.bottom, 20)
            }.background(NextStyle.page).navigationTitle("مركز التنزيل")
        }
    }

    private var operationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(signing.title).font(.headline).lineLimit(2)
                Spacer()
                if signing.busy { ProgressView() }
                else { Image(systemName: signing.phase == .ready ? "checkmark.circle.fill" : "exclamationmark.circle.fill").foregroundStyle(signing.phase == .ready ? .green : .orange) }
            }
            Text(signing.detail).font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
            if signing.phase == .downloading {
                if let value = signing.progress { ProgressView(value: value); Text((signing.transfer?.bytesText ?? "") + " · \(Int(value * 100))٪").font(.caption.monospacedDigit()) }
                else { ProgressView() }
                Button("إلغاء التنزيل", role: .cancel) { signing.cancel() }.buttonStyle(.bordered)
            }
            if signing.phase == .ready {
                Button("إعادة طلب التثبيت") { signing.installSigned() }.buttonStyle(.borderedProminent)
                if let url = signing.signedURL { NextShareButton(item: url) { Label("تصدير IPA الموقّع", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) }
            }
            if let notice = signing.signingNotice {
                DisclosureGroup("معلومات ملف التوقيع") {
                    Text(notice).font(.caption).textSelection(.enabled)
                }.font(.caption)
            }
            DisclosureGroup("تفاصيل العملية") {
                Text(signing.log.joined(separator: "\n")).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.font(.caption)
        }.padding(18).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
    }

    private var settings: some View {
        NavigationView {
            Form {
                Section {
                    HStack(spacing: 15) {
                        Image("TAIFPlusIcon").resizable().frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("TAIF PLUS").font(.title2.bold())
                            Text("1.0.0").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section("المظهر") {
                    Picker("وضع العرض", selection: $appearanceMode) {
                        ForEach(TaifAppearanceMode.allCases) { mode in Text(mode.title).tag(mode.rawValue) }
                    }.pickerStyle(.segmented)
                    Text("الفاتح أبيض صافي، والداكن فحمي. تلقائي يتبع مظهر الجهاز، ونحفظ اختيارك للمرة الجاية.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("التوقيع داخل جهازك") {
                    Button { showCertificates = true } label: { settingRow("شهادة P12", value: certificates.selected?.displayName ?? "أضف الشهادة", icon: "key.fill") }
                    Button { showProfiles = true } label: { settingRow("ملف provisioning", value: profiles.selected?.displayName ?? "أضف ملف الحماية", icon: "doc.badge.gearshape.fill") }
                    if let profile = profiles.selected {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("معرّف ملف التوقيع").font(.caption)
                            Text(profile.applicationIdentifier ?? "غير موجود في الملف")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                .environment(\.layoutDirection, .leftToRight)
                            Text("نحافظ على معرّف كل تطبيق ونستخدم بيانات ملف التوقيع كما هي.").font(.caption)
                        }.foregroundStyle(.secondary)
                    }
                    Text("اختَر الشهادة وملفها المتطابقين. التطبيق يقبل الشهادات بدون كلمة مرور أيضًا.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("المتجر") {
                    Toggle("إشعارات التنزيل والتوقيع", isOn: $downloadNotifications)
                    Button("إعدادات إشعارات iOS") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    Text("اسم التطبيق وأيقونته والحجم المنزّل يظهرن في الإشعار عند السماح من iOS.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button { showSources = true } label: { settingRow("مصادر التطبيقات", value: "\(repositories.visibleRepositories.count) مصدر", icon: "shippingbox.fill") }
                    Button { showImporter = true; tab = 1 } label: { settingRow("استيراد IPA", value: "من ملفات جهازك", icon: "square.and.arrow.down.fill") }
                }
                Section("تواصل مع TAIF") {
                    Link(destination: URL(string: "https://t.me/tife_store")!) { Label("قناة المتجر", systemImage: "paperplane.fill") }
                    Link(destination: URL(string: "https://t.me/tife_store1")!) { Label("المالك", systemImage: "person.crop.circle.badge.checkmark") }
                    Link(destination: URL(string: "https://t.me/YG8_1")!) { Label("المشرف والمطور", systemImage: "curlybraces") }
                }
                Section("اشتراك TAIF PLUS") { NextSubscriptionDetails() }
                Section {
                    Text("بعد نجاح التوقيع يفتح طلب iOS تلقائيًا؛ وافق على النافذة. قبول التثبيت يعتمد على صلاحية شهادة Apple وتوافق ملف provisioning مع جهازك.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.taifFormSurface().navigationTitle("الإعدادات")
        }
    }

    private func settingRow(_ name: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 30).foregroundStyle(NextStyle.accent)
            VStack(alignment: .leading, spacing: 3) { Text(name).foregroundStyle(.primary); Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer(); Image(systemName: "chevron.left").font(.caption).foregroundStyle(.tertiary)
        }.padding(.vertical, 5)
    }

    private func refresh() async {
        await withTaskGroup(of: Void.self) { group in
            for repository in repositories.visibleRepositories { group.addTask { await repositories.refresh(repository) } }
        }
    }
}

private struct NextSubscriptionDetails: View {
    @EnvironmentObject private var access: NextLicenseStore
    var body: some View {
        if let license = access.license {
            HStack { Text("الاسم"); Spacer(); Text(license.name).foregroundStyle(.secondary) }
            HStack { Text("انتهاء الاشتراك"); Spacer(); Text(Date(timeIntervalSince1970: TimeInterval(license.expires)), style: .date).foregroundStyle(.secondary) }
        }
        Text(access.installationID).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
    }
}



private struct NextTransferBanner: View {
    let title: String
    let iconURL: URL?
    let fraction: Double?
    let detail: String
    let ready: Bool
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    if let iconURL { CachedAppIcon(url: iconURL, size: 38, cornerRadius: 11) }
                    else { Image("TAIFPlusIcon").resizable().frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 11)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(detail).font(.system(size: 10)).foregroundColor(.white.opacity(0.65)).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    ZStack {
                        Circle().stroke(.white.opacity(0.12), lineWidth: 2)
                        if ready { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(TaifPalette.cherry) }
                        else if let fraction {
                            Circle().trim(from: 0, to: fraction).stroke(TaifPalette.cherry, style: StrokeStyle(lineWidth: 2, lineCap: .round)).rotationEffect(.degrees(-90))
                            Text("\(Int(fraction * 100))").font(.system(size: 8, weight: .bold, design: .rounded))
                        } else { ProgressView().tint(.white).scaleEffect(0.65) }
                    }.frame(width: 28, height: 28)
                }
            }.buttonStyle(.plain)
            Button(action: onClose) {
                Image(systemName: ready ? "xmark" : "stop.fill").font(.system(size: 10, weight: .semibold))
                    .frame(width: 26, height: 32).foregroundColor(.white.opacity(0.7))
            }.buttonStyle(.plain).accessibilityLabel(ready ? "إخفاء" : "إلغاء العملية")
        }
        .foregroundColor(.white).padding(.horizontal, 12).padding(.vertical, 10)
        .background(Color(red: 0.06, green: 0.045, blue: 0.055), in: RoundedRectangle(cornerRadius: 23))
        .overlay(RoundedRectangle(cornerRadius: 23).stroke(TaifPalette.cherry.opacity(0.18), lineWidth: 0.8))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }
}
