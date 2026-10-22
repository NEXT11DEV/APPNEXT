import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var access: NextLicenseStore
    @AppStorage("app.language") private var languageCode = AppLanguage.arabic.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 18) {
                        Image("NextPlusIcon")
                            .resizable().scaledToFit().frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("NEXT PlUS").font(.title2.bold())
                            Text("متجرك وتوقيعك داخل الآيفون")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text("1.0.0").font(.caption.monospaced())
                        }
                    }.padding(.vertical, 8)
                }
                if let license = access.license {
                    Section("اشتراكك") {
                        LabeledContent("الاسم", value: license.name)
                        LabeledContent("ينتهي في") {
                            Text(Date(timeIntervalSince1970: TimeInterval(license.expires)), style: .date)
                        }
                        Text(access.installationID)
                            .font(.caption.monospaced()).textSelection(.enabled)
                            .environment(\.layoutDirection, .leftToRight)
                    }
                }
                Section("اللغة") {
                    Picker("Language", selection: $languageCode) {
                        Text("العربية").tag(AppLanguage.arabic.rawValue)
                        Text("English").tag(AppLanguage.english.rawValue)
                    }
                    .onChange(of: languageCode) { _ in
                        UserDefaults.standard.set(true, forKey: "app.language.userSelected")
                    }
                }
                Section("التوقيع والتثبيت") {
                    Text("ملفات P12 وprovisioning تبقى داخل التطبيق. اختر تطبيقك من المصادر أو استورده، وبعدها وقّعه وثبّته بشهادتك الخاصة.")
                    Text("كود اشتراك NEXT PlUS يفعّل المتجر؛ تثبيت المتجر والتطبيقات يحتاج شهادة Apple وملف provisioning صالحين يشملان جهازك.")
                        .foregroundStyle(.secondary)
                }
                Section("المكونات والحقوق") {
                    Text("مبني على مشروع iStore الأصلي لعبدالباسط خضير، ومحرك zsign ومكتبة OpenSSL. تم الاحتفاظ بتراخيصهم وإشعارات الحقوق في المشروع.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link("مصدر iStore الأصلي", destination: URL(string: "https://github.com/hggdet/iStore-iOS")!)
                    Link("محرك zsign", destination: URL(string: "https://github.com/zhlynn/zsign")!)
                }
            }.navigationTitle("NEXT PlUS")
        }
    }
}
