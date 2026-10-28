import SwiftUI

struct NextAppDetails: View {
    let app: RepoApp
    let busy: Bool
    let install: (RepoApp, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    private let accent = TaifPalette.accent

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 20) {
                        Text("TAIF / APP PROFILE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2).foregroundColor(.white.opacity(0.5))
                        CachedAppIcon(url: app.iconURL, size: 112, cornerRadius: 29)
                            .shadow(color: .black.opacity(0.4), radius: 24, y: 16)
                        Text(app.name).font(.system(size: 28, weight: .bold)).multilineTextAlignment(.center).foregroundColor(.white)
                        Text(app.developerName ?? "من مكتبة TAIF").font(.system(size: 12)).foregroundColor(.white.opacity(0.65))
                    }.frame(maxWidth: .infinity).padding(.vertical, 30).padding(.horizontal, 20)
                        .background(TaifPalette.hero, in: RoundedRectangle(cornerRadius: 32))
                    HStack(spacing: 12) {
                        Button { install(app, false); dismiss() } label: {
                            Label("تثبيت التطبيق", systemImage: "arrow.down.circle.fill").frame(maxWidth: .infinity).padding(.vertical, 13)
                        }.buttonStyle(.borderedProminent).disabled(busy || app.downloadURL == nil)
                        Button { install(app, true); dismiss() } label: { Label("نسخة ثانية", systemImage: "plus.square.on.square").padding(.vertical, 13) }
                            .buttonStyle(.bordered).disabled(busy || app.downloadURL == nil)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        fact("الحجم", value: Self.sizeText(app.size))
                        fact("الإصدار", value: app.version ?? "غير مذكور")
                        fact("الإصدارات", value: "\(app.versions.count)")
                    }.padding(.vertical, 14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                    VStack(alignment: .leading, spacing: 10) {
                        Text("عن التطبيق").font(.title3.bold())
                        Text(app.localizedDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? app.localizedDescription! : "المصدر ما موفّر وصف لهذا التطبيق.")
                            .font(.subheadline).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("معرّف التطبيق").font(.caption).foregroundStyle(.secondary)
                        Text(app.bundleIdentifier).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                    Text("الإصدارات المتوفرة").font(.title3.bold())
                    if app.versions.isEmpty { Text("المصدر ما موفّر قائمة إصدارات.").font(.subheadline).foregroundStyle(.secondary) }
                    ForEach(app.versions) { release in
                        HStack(spacing: 12) {
                            Image(systemName: "shippingbox.fill").foregroundColor(accent).frame(width: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(release.version.map { "الإصدار \($0)" } ?? "إصدار غير مسمّى").font(.subheadline.bold())
                                Text(Self.sizeText(release.size)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("تثبيت") {
                                do { install(try app.selectingVersion(release), false); dismiss() }
                                catch { self.error = "تعذر قراءة معلومات هذا الإصدار." }
                            }.buttonStyle(.bordered).disabled(busy || release.downloadURL == nil)
                        }.padding(14).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 16))
                    }
                    if let error { Text(error).font(.caption).foregroundColor(.red) }
                }.padding(20)
            }.background(TaifPalette.page).navigationTitle("تفاصيل التطبيق").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle()).tint(accent)
    }

    private func fact(_ title: String, value: String) -> some View {
        VStack(spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 12, weight: .semibold)).multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity)
    }
    static func sizeText(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "غير مذكور" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
