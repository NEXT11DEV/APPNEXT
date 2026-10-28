import SwiftUI
import UIKit

struct TaifEditorialArt: View {
    var body: some View {
        if let url = Bundle.main.url(forResource: "TaifEditorial", withExtension: "jpg"), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFill()
        } else { TaifPalette.hero }
    }
}

struct TaifHome: View {
    let apps: [RepoApp]
    let total: Int
    let openCatalog: (String) -> Void
    let openDetails: (RepoApp) -> Void
    let openFiles: () -> Void
    let openAccount: () -> Void
    let importIPA: () -> Void
    private var selections: [RepoApp] {
        var seen = Set<String>()
        return Array(apps.lazy.filter { seen.insert($0.name.lowercased()).inserted }.prefix(12))
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 23) {
                header
                hero
                shortcuts
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("مساحة للاكتشاف").font(.system(size: 22, weight: .bold))
                        Text("من مكتبة تضم \(total) تطبيق ولعبة").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("عرض الكل") { openCatalog("الكل") }.font(.system(size: 11, weight: .semibold))
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(Array(selections.enumerated()), id: \.element.id) { index, app in
                            cover(app, index: index)
                        }
                    }.padding(.vertical, 4)
                }
                importCard
                HStack { Text("قريبين منك").font(.system(size: 20, weight: .bold)); Spacer(); Text("TAIF COMMUNITY").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary) }
                Link(destination: URL(string: "https://t.me/tife_store")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "paperplane.fill").frame(width: 43, height: 43).background(TaifPalette.accent.opacity(0.10), in: Circle())
                        VStack(alignment: .leading, spacing: 5) { Text("التحديثات والتطوير").font(.system(size: 14, weight: .bold)); Text("كل جديد من TAIF، بمكان واحد.").font(.system(size: 11)).foregroundStyle(.secondary) }
                        Spacer(); Image(systemName: "arrow.up.left")
                    }.foregroundStyle(TaifPalette.accent).padding(16).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 23))
                }
            }.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 26)
        }.background(TaifPalette.page)
    }
    private var header: some View {
        HStack(spacing: 11) {
            Button(action: openAccount) { Image("TAIFPlusIcon").resizable().frame(width: 41, height: 41).clipShape(RoundedRectangle(cornerRadius: 13)) }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 3) { Text("TAIF").font(.system(size: 24, weight: .black, design: .rounded)); Text("PLUS").font(.system(size: 9, weight: .black)).tracking(1).foregroundStyle(TaifPalette.accent) }
                Text("هلا بيك، هاي مساحتك.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: openFiles) { Image(systemName: "arrow.down.to.line").font(.system(size: 19, weight: .medium)).frame(width: 42, height: 42).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 15)) }.accessibilityLabel("ملفاتي وتنزيلاتي")
        }.foregroundStyle(TaifPalette.ink)
    }
    private var hero: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                TaifEditorialArt().frame(width: g.size.width, height: g.size.height).clipped()
                LinearGradient(colors: [.black.opacity(0.10), .clear, .black.opacity(0.45)], startPoint: .leading, endPoint: .trailing)
                VStack(alignment: .leading, spacing: 11) {
                    Label("تجربة بطابع TAIF", systemImage: "sparkle").font(.system(size: 9, weight: .medium)).foregroundColor(.white.opacity(0.70))
                    Text("على ذوقك.\nبكل تفاصيله.").font(.system(size: 26, weight: .bold)).foregroundColor(.white).lineSpacing(2)
                    Button { openCatalog("الكل") } label: {
                        HStack(spacing: 7) { Text("ادخل عالم TAIF"); Image(systemName: "arrow.left") }.font(.system(size: 10, weight: .bold)).padding(.horizontal, 14).padding(.vertical, 11).foregroundColor(.black).background(.white, in: Capsule())
                    }.buttonStyle(.plain)
                }.frame(width: g.size.width * 0.52, alignment: .leading).padding(.leading, 18)
            }.clipShape(RoundedRectangle(cornerRadius: 29))
        }.frame(height: 222)
    }
    private var shortcuts: some View {
        HStack(spacing: 10) {
            shortcut("التطبيقات", icon: "square.grid.2x2.fill", action: { openCatalog("تطبيقات") })
            shortcut("الألعاب", icon: "gamecontroller.fill", action: { openCatalog("ألعاب") })
            shortcut("ملفاتي", icon: "folder.fill", action: openFiles)
        }
    }
    private func shortcut(_ name: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) { Image(systemName: icon).foregroundStyle(TaifPalette.accent); Text(name).foregroundStyle(TaifPalette.ink) }
                .font(.system(size: 11, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 17).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 18))
        }.buttonStyle(.plain)
    }
    private func cover(_ app: RepoApp, index: Int) -> some View {
        Button { openDetails(app) } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomTrailing) {
                    LinearGradient(colors: [TaifPalette.accent.opacity(index % 2 == 0 ? 0.06 : 0.18), TaifPalette.inset], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().stroke(TaifPalette.accent.opacity(0.09), lineWidth: 1).frame(width: 180, height: 180).offset(x: 35, y: -24)
                    CachedAppIcon(url: app.iconURL, size: 112, cornerRadius: 28).rotationEffect(.degrees(-12)).shadow(color: .black.opacity(0.17), radius: 18, y: 12).padding(.trailing, 26).padding(.bottom, 22)
                    Text(app.category ?? "اكتشفه الآن").font(.system(size: 8, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 6).background(.ultraThinMaterial, in: Capsule()).padding(12)
                }.frame(height: 166).clipped()
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(app.name).font(.system(size: 14, weight: .bold)).lineLimit(1).foregroundStyle(TaifPalette.ink)
                        Text(metadata(app)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "arrow.up.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(TaifPalette.accent)
                }.padding(14)
            }.frame(width: 230).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 25)).clipShape(RoundedRectangle(cornerRadius: 25))
        }.buttonStyle(.plain)
    }
    private func metadata(_ app: RepoApp) -> String {
        var result = app.version.map { "v" + $0 } ?? "IPA"
        if let size = app.size, size > 0 { result += " · " + ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
        return result
    }
    private var importCard: some View {
        Button(action: importIPA) {
            HStack(spacing: 15) {
                Image(systemName: "doc.badge.plus").font(.system(size: 30, weight: .light)).frame(width: 52, height: 58)
                VStack(alignment: .leading, spacing: 7) { Text("ملفك، توقيعك، تطبيقك.").font(.system(size: 17, weight: .bold)); Text("أضف IPA من جهازك وابدأ من هنا.").font(.system(size: 11)).foregroundStyle(.secondary) }
                Spacer(); Image(systemName: "plus")
            }.foregroundStyle(TaifPalette.ink).padding(21).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 25))
                .overlay(RoundedRectangle(cornerRadius: 25).stroke(TaifPalette.accent.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
        }.buttonStyle(.plain)
    }
}

struct TaifCatalog: View {
    let apps: [RepoApp]
    let total: Int
    let more: Bool
    let busy: Bool
    @Binding var query: String
    @Binding var category: String
    let details: (RepoApp) -> Void
    let install: (RepoApp) -> Void
    let duplicate: (RepoApp) -> Void
    let loadMore: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { VStack(alignment: .leading, spacing: 6) { Text("المتجر").font(.system(size: 32, weight: .bold)); Text("كل شي يستاهل التجربة.").font(.system(size: 12)).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "square.grid.2x2").font(.system(size: 30, weight: .ultraLight)).foregroundStyle(TaifPalette.accent) }
                HStack { Image(systemName: "magnifyingglass").foregroundStyle(TaifPalette.accent); TextField("ابحث بالتطبيقات والألعاب", text: $query).font(.system(size: 13)).textInputAutocapitalization(.never).autocorrectionDisabled(); if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }.foregroundStyle(.secondary) } }.padding(16).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 18))
                Picker("التصنيف", selection: $category) { Text("الكل").tag("الكل"); Text("التطبيقات").tag("تطبيقات"); Text("الألعاب").tag("ألعاب") }.pickerStyle(.segmented)
                HStack { Text("\(apps.count) معروض"); Spacer(); Text("\(total) بالمكتبة") }.font(.system(size: 10)).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 14) {
                    ForEach(apps) { app in
                        VStack(alignment: .leading, spacing: 12) {
                            Button { details(app) } label: {
                                VStack(alignment: .leading, spacing: 12) {
                                    CachedAppIcon(url: app.iconURL, size: 68, cornerRadius: 20)
                                    Text(app.name).font(.system(size: 14, weight: .bold)).lineLimit(2).frame(height: 37, alignment: .topLeading).foregroundStyle(TaifPalette.ink)
                                    Text(app.version.map { "v" + $0 } ?? "IPA").font(.system(size: 10)).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                            HStack {
                                Button { install(app) } label: { Text("تثبيت").font(.system(size: 11, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 10).foregroundColor(.white).background(TaifPalette.ruby, in: Capsule()) }.disabled(busy || app.downloadURL == nil)
                                Menu { Button("التفاصيل والإصدارات") { details(app) }; Button("إنشاء نسخة ثانية") { duplicate(app) }.disabled(busy || app.downloadURL == nil) } label: { Image(systemName: "ellipsis").frame(width: 22, height: 32) }.accessibilityLabel("خيارات " + app.name)
                            }
                        }.padding(15).background(TaifPalette.card, in: RoundedRectangle(cornerRadius: 24)).onAppear { if app.id == apps.last?.id { loadMore() } }
                    }
                }
                if apps.isEmpty { Text("ما لقينا نتائج. جرّب بحثًا آخر.").foregroundStyle(.secondary).padding(.vertical, 30) }
                if more { Button("عرض 30 تطبيق إضافي", action: loadMore).frame(maxWidth: .infinity).padding(12) }
            }.padding(20)
        }.background(TaifPalette.page)
    }
}
