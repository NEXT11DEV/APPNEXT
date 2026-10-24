import SwiftUI
import UIKit

struct NextAccessGate<Content: View>: View {
    @StateObject private var access = NextLicenseStore()
    @State private var code = ""
    @Environment(\.scenePhase) private var scenePhase
    private let content: Content
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    private var previewEnabled: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.environment["NEXT_UI_PREVIEW"] == "1"
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            if access.license != nil || previewEnabled {
                content.environmentObject(access)
            } else {
                NavigationView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Image("IDKPlusIcon").resizable().scaledToFit()
                                .frame(width: 86, height: 86).clipShape(RoundedRectangle(cornerRadius: 23))
                                .padding(.top, 38)
                            Text("idk plus")
                                .font(.system(size: 38, weight: .black, design: .rounded))
                            Text("تطبيقاتك. توقيعك. بمكان واحد.")
                                .font(.title3.bold())
                            Text("انسخ معرّفك وأرسله لصاحب المتجر حتى يعطيك كود اشتراك خاص بهذا التطبيق على جهازك.")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 12) {
                                Text("معرّف المشترك").font(.headline)
                                Text(access.installationID)
                                    .font(.system(.footnote, design: .monospaced))
                                    .textSelection(.enabled)
                                    .environment(\.layoutDirection, .leftToRight)
                                Button("نسخ المعرّف") { UIPasteboard.general.string = access.installationID }
                                    .buttonStyle(.bordered)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                            VStack(alignment: .leading, spacing: 12) {
                                Text("كود التفعيل").font(.headline)
                                TextEditor(text: $code)
                                    .frame(minHeight: 100, maxHeight: 140)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .font(.system(.footnote, design: .monospaced))
                                    .padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                                    .environment(\.layoutDirection, .leftToRight)
                                Button("تفعيل الاشتراك") { access.activate(code) }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            }
                            if !access.message.isEmpty {
                                Text(access.message).foregroundStyle(.red).font(.footnote)
                            }
                            Text("بعد التفعيل أضف شهادة P12 وملف provisioning. التوقيع يصير داخل الآيفون؛ ما يحتاج حاسبة شغّالة أو سيرفر توقيع.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(26).frame(maxWidth: 600)
                    }
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGroupedBackground))
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .onReceive(timer) { _ in access.refresh() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { access.refresh() }
        }
    }
}

