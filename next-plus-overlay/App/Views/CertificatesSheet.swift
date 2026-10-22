import SwiftUI

struct CertificatesSheet: View {
    @EnvironmentObject private var store: CertificateStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var selectedFile: URL?
    @State private var password = ""
    @State private var remember = true
    @State private var error: String?

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("شهادات P12")) {
                    ForEach(store.certificates) { certificate in
                        Button { store.select(certificate.id) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: store.selectedID == certificate.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(certificate.displayName).foregroundColor(.primary)
                                    if let expiration = certificate.notAfter { Text(expiration, style: .date).font(.caption).foregroundColor(.secondary) }
                                }
                            }.padding(.vertical, 4)
                        }
                    }.onDelete { offsets in
                        let removed = offsets.map { store.certificates[$0] }
                        for certificate in removed { store.delete(certificate) }
                    }
                    Button("استيراد شهادة P12") { showImporter = true }
                }
                if let selectedFile {
                    Section(header: Text("استيراد الشهادة"), footer: Text("اترك كلمة المرور فارغة إذا الشهادة بدون كلمة مرور.")) {
                        Text(selectedFile.lastPathComponent).font(.caption)
                        SecureField("كلمة مرور P12", text: $password)
                        Toggle("حفظ كلمة المرور على هذا الجهاز", isOn: $remember)
                        Button("حفظ واختيار الشهادة") { importCertificate() }
                        Button("إلغاء", role: .cancel) { self.selectedFile = nil; password = "" }
                    }
                }
                if let error { Section { Text(error).font(.footnote).foregroundColor(.red).textSelection(.enabled) } }
            }.navigationTitle("شهادة التوقيع")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
                .sheet(isPresented: $showImporter) {
                    ForgeDocumentPicker { urls in
                        showImporter = false
                        guard let url = urls.first else { return }
                        guard url.pathExtension.lowercased() == "p12" else { error = "اختَر ملف شهادة بامتداد p12."; return }
                        selectedFile = url; password = ""; error = nil
                    } onCancel: { showImporter = false }
                }
        }.navigationViewStyle(StackNavigationViewStyle())
    }

    private func importCertificate() {
        guard let selectedFile else { return }
        switch store.importCertificate(from: selectedFile, password: password, rememberPassword: remember) {
        case .success: self.selectedFile = nil; password = ""; error = nil
        case .failure(let issue):
            switch issue {
            case .unreadable: error = "تعذر قراءة الشهادة. أعد اختيارها من الملفات."
            case .badPassword: error = "تعذر فتح P12. تحقق من الملف وكلمة مروره."
            case .copyFailed: error = "تعذر حفظ الشهادة على الجهاز."
            }
        }
    }
}
