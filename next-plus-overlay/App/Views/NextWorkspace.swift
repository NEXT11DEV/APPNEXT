import SwiftUI
import UniformTypeIdentifiers

private enum NextStyle {
    static let purple = Color(red: 0.48, green: 0.32, blue: 0.91)
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

struct NextWorkspace: View {
    @ObservedObject var certificates: CertificateStore
    @ObservedObject var profiles: ProfileStore
    @ObservedObject var history: HistoryStore
    @ObservedObject var installer: InstallController
    @ObservedObject var repositories: RepositoryStore
    @StateObject private var signing: NextSigningCoordinator
    @State private var tab = 0
    @State private var query = ""
    @State private var showSources = false
    @State private var showCertificates = false
    @State private var showProfiles = false
    @State private var showImporter = false
    @State private var password = ""
    @State private var category = "الكل"
    @State private var refreshed = false

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
        TabView(selection: $tab) {
            store.tabItem { Label("المتجر", systemImage: "square.grid.2x2.fill") }.tag(0)
            library.tabItem { Label("المكتبة", systemImage: "square.stack.3d.up.fill") }.tag(1)
            settings.tabItem { Label("الإعدادات", systemImage: "slider.horizontal.3") }.tag(2)
        }
        .onReceive(repositories.$catalog) { catalog in
            rebuildCatalog(repositories: repositories.repositories, catalog: catalog)
        }
        .onReceive(repositories.$repositories) { repositories in
            rebuildCatalog(repositories: repositories, catalog: self.repositories.catalog)
        }
        .onChange(of: query) { _ in resetPage() }
        .onChange(of: category) { _ in resetPage() }
        .navigationViewStyle(StackNavigationViewStyle())
        .tint(NextStyle.purple)
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
                    Button("متابعة التوقيع") { signing.providePassword(password); password = ""; tab = 1 }
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

    private var store: some View {
        NavigationView {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Color.clear.frame(height: 0).id("catalog-top")
                    HStack(spacing: 13) {
                        Image("IDKPlusIcon").resizable().scaledToFit().frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 15))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("idk plus").font(.system(size: 26, weight: .heavy, design: .rounded)).lineLimit(1).minimumScaleFactor(0.75)
                            Text("مساحتك للتطبيقات").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { Task { await refresh() } } label: {
                            Image(systemName: "arrow.clockwise").font(.headline).frame(width: 36, height: 42)
                        }.accessibilityLabel("تحديث التطبيقات").disabled(repositories.loadingRepoID != nil)
                        Button { showSources = true } label: {
                            Image(systemName: "plus").font(.title3.bold()).frame(width: 42, height: 42)
                                .background(NextStyle.card, in: Circle())
                        }.accessibilityLabel("إدارة المصادر")
                    }
                    statusCard
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("ابحث عن تطبيق أو لعبة", text: $query)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") } }
                    }.padding(14).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 16))
                    HStack(spacing: 10) {
                        ForEach(["الكل", "تطبيقات", "ألعاب"], id: \.self) { value in
                            Button { category = value } label: {
                                Text(value).font(.subheadline.weight(.semibold)).padding(.horizontal, 20).padding(.vertical, 9)
                                    .foregroundStyle(category == value ? Color.white : Color.primary)
                                    .background(category == value ? NextStyle.purple : NextStyle.card, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    HStack {
                        Text(query.isEmpty ? "اكتشف التطبيقات" : "نتائج البحث").font(.title3.bold())
                        Spacer()
                        Text(query.isEmpty ? "عرض \(apps.count) من \(allApps.count)" : "\(apps.count) نتيجة\(hasMoreApps ? "+" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if apps.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "square.stack.3d.up").font(.system(size: 35)).foregroundStyle(NextStyle.purple)
                            Text(repositories.repositories.isEmpty ? "ابدأ بإضافة مصدرك" : "لا توجد نتائج حاليًا").font(.headline)
                            Text(repositories.repositories.isEmpty ? "أضف رابط مصدر تطبيقات، أو استورد IPA من مكتبتك." : "اسحب للتحديث أو غيّر البحث والتصنيف.")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("إدارة المصادر") { showSources = true }.buttonStyle(.borderedProminent)
                        }.frame(maxWidth: .infinity).padding(28).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 22))
                    }
                    LazyVStack(spacing: 12) {
                        ForEach(apps) { app in
                            appCard(app).onAppear {
                                if app.id == apps.last?.id { showMore() }
                            }
                        }
                    }
                    if hasMoreApps {
                        Button("عرض ٣٠ تطبيق إضافي") { showMore() }
                            .font(.subheadline).frame(maxWidth: .infinity).padding(.vertical, 12)
                    }
                    if !repositories.fetchError.isEmpty {
                        Text("تعذر تحديث بعض المصادر. افتح إدارة المصادر لعرض تفاصيلها.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                }.padding(20).padding(.bottom, 20)
            }
            .background(NextStyle.page).navigationBarHidden(true)
            .onChange(of: query) { _ in scroll.scrollTo("catalog-top", anchor: .top) }
            .onChange(of: category) { _ in scroll.scrollTo("catalog-top", anchor: .top) }
            .refreshable { await refresh() }
            .task {
                guard !refreshed else { return }; refreshed = true
                while !repositories.catalogCacheLoaded { try? await Task.sleep(nanoseconds: 20_000_000) }
                await refresh()
            }
            }
        }
    }

    private var statusCard: some View {
        Button { tab = signing.busy || signing.phase == .ready ? 1 : 2 } label: {
            HStack(spacing: 12) {
                Image(systemName: signing.busy ? "arrow.down.circle.fill" : certificates.selected != nil && profiles.selected != nil ? "checkmark.seal.fill" : "key.horizontal.fill")
                    .font(.title2).foregroundStyle(NextStyle.purple)
                VStack(alignment: .leading, spacing: 4) {
                    Text(signing.busy ? signing.title : certificates.selected != nil && profiles.selected != nil ? "ملفات التوقيع مضافة" : "جهّز توقيعك مرة واحدة")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                    Text(signing.busy ? signing.detail : "شهادة P12 + ملف provisioning")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(); Image(systemName: "chevron.left").font(.caption.bold()).foregroundStyle(.tertiary)
            }.padding(17).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain)
    }

    private func appCard(_ app: RepoApp) -> some View {
        HStack(spacing: 13) {
            CachedAppIcon(url: app.iconURL, size: 58, cornerRadius: 15)
            VStack(alignment: .leading, spacing: 5) {
                Text(app.name).font(.system(size: 15, weight: .semibold)).lineLimit(2)
                HStack(spacing: 7) {
                    Text(app.version.map { "v\($0)" } ?? "IPA")
                    if let size = app.size { Text("·"); Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                signing.start(.repository(app))
                if signing.busy { tab = 1 }
            } label: {
                Text("تثبيت").font(.system(size: 13, weight: .bold))
                    .frame(width: 72, height: 36).background(NextStyle.purple.opacity(0.11), in: Capsule())
            }.buttonStyle(.plain).disabled(signing.busy || app.downloadURL == nil)
                .accessibilityLabel("تنزيل وتوقيع \(app.name)")
        }.padding(14).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
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
                            .background(LinearGradient(colors: [NextStyle.purple.opacity(0.8), NextStyle.purple], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 22))
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
                                Image(systemName: "app.badge.checkmark").font(.title).foregroundStyle(NextStyle.purple)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.inputName).font(.headline).lineLimit(2)
                                    Text(record.bundleId).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                            }
                            HStack {
                                Button("تثبيت") { installer.install(ipa: history.outputURL(for: record), bundleId: record.bundleId, version: record.version, title: record.inputName) }
                                    .buttonStyle(.borderedProminent).disabled(!history.fileExists(for: record) || signing.busy)
                                if history.fileExists(for: record) { NextShareButton(item: history.outputURL(for: record)) { Label("مشاركة IPA", systemImage: "square.and.arrow.up") }.buttonStyle(.bordered) }
                            }
                        }.padding(18).background(NextStyle.card, in: RoundedRectangle(cornerRadius: 20))
                    }
                }.padding(20).padding(.bottom, 20)
            }.background(NextStyle.page).navigationTitle("المكتبة")
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
                if let value = signing.progress { ProgressView(value: value); Text("\(Int(value * 100))٪").font(.caption.monospacedDigit()) }
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
                        Image("IDKPlusIcon").resizable().frame(width: 62, height: 62).clipShape(RoundedRectangle(cornerRadius: 17))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("idk plus").font(.title2.bold())
                            Text("1.1.0").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
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
                    Button { showSources = true } label: { settingRow("مصادر التطبيقات", value: "\(repositories.visibleRepositories.count) مصدر", icon: "shippingbox.fill") }
                    Button { showImporter = true; tab = 1 } label: { settingRow("استيراد IPA", value: "من ملفات جهازك", icon: "square.and.arrow.down.fill") }
                }
                Section("اشتراك idk plus") { NextSubscriptionDetails() }
                Section {
                    Text("بعد نجاح التوقيع يفتح طلب iOS تلقائيًا؛ وافق على النافذة. قبول التثبيت يعتمد على صلاحية شهادة Apple وتوافق ملف provisioning مع جهازك.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle("الإعدادات")
        }
    }

    private func settingRow(_ name: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 30).foregroundStyle(NextStyle.purple)
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


