import SwiftUI

/// TAIF's own discovery surface. The signing engine is injected as actions.
struct TaifDiscovery: View {
    let apps: [RepoApp]
    let total: Int
    let more: Bool
    let busy: Bool
    @Binding var query: String
    @Binding var category: String
    let details: (RepoApp) -> Void
    let install: (RepoApp) -> Void
    let loadMore: () -> Void
    let importIPA: () -> Void
    let settings: () -> Void
    private let P = TaifPalette.accent
    @State private var featured = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                masthead
                if query.isEmpty && category == "الكل" && !apps.isEmpty { showcase }
                search
                filters
                HStack {
                    Text(query.isEmpty ? "كل الاحتمالات" : "نتائجك").font(.system(size: 24, weight: .bold))
                    Spacer()
                    Text("\(apps.count) / \(total)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                }
                LazyVStack(spacing: 0) {
                    ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                        catalogLine(app, number: index + 1)
                            .onAppear { if app.id == apps.last?.id { loadMore() } }
                    }
                }
                if apps.isEmpty { Text("جرّب اسمًا أو تصنيفًا آخر.").foregroundStyle(.secondary).padding(.vertical, 30) }
                if more { Button("اكتشف المزيد") { loadMore() }.frame(maxWidth: .infinity).padding(15) }
                Link(destination: URL(string: "https://t.me/tife_store")!) {
                    HStack { Text("ابقَ قريبًا من TAIF"); Spacer(); Image(systemName: "arrow.up.left") }
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(P).padding(.vertical, 20)
                }
            }.padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 24)
        }.background(TaifPalette.page)
    }
    private var masthead: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("TAIF⁺").font(.system(size: 32, weight: .black, design: .rounded)).tracking(-2)
                Text("مساحة لكل شغف").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: importIPA) { Image(systemName: "plus.app").font(.system(size: 22)).frame(width: 42, height: 42) }.accessibilityLabel("استيراد IPA")
            Button(action: settings) { Image("TAIFPlusIcon").resizable().frame(width: 39, height: 39).clipShape(Circle()) }.accessibilityLabel("حسابي والإعدادات")
        }.foregroundStyle(TaifPalette.ink)
    }
    private var showcase: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("تحت الضوء").font(.system(size: 12, weight: .bold))
                Spacer()
                Text("SWIPE TO EXPLORE").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.3).foregroundStyle(.secondary)
            }
            TabView(selection: $featured) {
                ForEach(Array(apps.prefix(5).enumerated()), id: \.offset) { index, app in
                    spotlight(app, index: index).tag(index)
                }
            }.tabViewStyle(.page(indexDisplayMode: .never)).frame(height: 300)
            HStack(spacing: 5) {
                ForEach(0..<min(5, apps.count), id: \.self) { index in
                    Capsule().fill(featured == index ? P : TaifPalette.line).frame(width: featured == index ? 25 : 5, height: 4)
                }
                Spacer()
                Text(String(format: "%02d / %02d", featured + 1, min(5, apps.count))).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
    }
    private func spotlight(_ app: RepoApp, index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color(red: 0.10, green: 0.035, blue: 0.055)
            GeometryReader { g in
                Circle().stroke(.white.opacity(0.10), lineWidth: 1).frame(width: 250, height: 250).offset(x: g.size.width * 0.32, y: -70)
                Circle().fill(TaifPalette.ruby.opacity(0.7)).frame(width: 180, height: 180).blur(radius: 55).offset(x: -55, y: -40)
                Text(String(format: "%02d", index + 1)).font(.system(size: 148, weight: .black, design: .rounded)).foregroundColor(.white.opacity(0.055)).offset(x: 12, y: -8)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(app.category ?? "من مكتبة TAIF").font(.system(size: 10, weight: .medium)).padding(.horizontal, 11).padding(.vertical, 7).background(.white.opacity(0.10), in: Capsule())
                    Spacer()
                    CachedAppIcon(url: app.iconURL, size: 104, cornerRadius: 26)
                        .rotationEffect(.degrees(-9)).shadow(color: .black.opacity(0.4), radius: 20, y: 15)
                }
                Spacer(minLength: 8)
                Text(app.name).font(.system(size: 27, weight: .bold)).lineLimit(2)
                HStack {
                    Text(app.version.map { "VERSION " + $0 } ?? "TAIF COLLECTION").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                    Spacer()
                    Button { details(app) } label: {
                        HStack(spacing: 9) { Text("استكشف"); Image(systemName: "arrow.up.left") }.font(.system(size: 12, weight: .bold)).padding(.horizontal, 16).padding(.vertical, 12).foregroundColor(.black).background(.white, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.padding(24).foregroundColor(.white)
        }.clipShape(RoundedRectangle(cornerRadius: 30)).padding(.horizontal, 1)
    }
    private var search: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass").foregroundStyle(P)
            TextField("شنو ببالك اليوم؟", text: $query).font(.system(size: 14)).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary) }
        }.padding(16).background(TaifPalette.inset, in: Capsule())
    }
    private var filters: some View {
        HStack(spacing: 10) {
            filter("الكل", icon: "sparkle")
            filter("ألعاب", icon: "gamecontroller")
            filter("تطبيقات", icon: "square.grid.2x2")
        }
    }
    private func filter(_ name: String, icon: String) -> some View {
        Button { category = name } label: {
            Label(name, systemImage: icon).font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 13)
                .foregroundColor(category == name ? TaifPalette.page : TaifPalette.ink)
                .background(category == name ? TaifPalette.ink : TaifPalette.inset, in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }
    private func catalogLine(_ app: RepoApp, number: Int) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { details(app) } label: {
                    HStack(spacing: 13) {
                        CachedAppIcon(url: app.iconURL, size: 54, cornerRadius: 16)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(app.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(TaifPalette.ink).lineLimit(1)
                            Text(app.version.map { "v" + $0 } ?? "IPA").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain)
                Button { install(app) } label: {
                    Image(systemName: "arrow.down").font(.system(size: 16, weight: .medium)).frame(width: 42, height: 42).background(P.opacity(0.10), in: Circle()).foregroundStyle(P)
                }.buttonStyle(.plain).disabled(busy || app.downloadURL == nil).accessibilityLabel("تثبيت " + app.name)
            }.padding(.vertical, 17)
            Rectangle().fill(TaifPalette.line).frame(height: 0.5)
        }
    }
}
