import SwiftUI

struct ProfilesSheet: View {
    @EnvironmentObject private var store: ProfileStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var error: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("ملفات provisioning")) {
                    ForEach(store.profiles) { profile in
                        Button { store.select(profile.id) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: store.selectedID == profile.id ? "checkmark.circle.fill" : "circle")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(profile.displayName).foregroundColor(.primary)
                                    if let identifier = profile.applicationIdentifier {
                                        Text(identifier).font(.caption).foregroundColor(.secondary)
                                            .textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                                    }
                                    if let expiration = profile.notAfter { Text(expiration, style: .date).font(.caption).foregroundColor(.secondary) }
                                }
                            }.padding(.vertical, 5)
                        }
                    }.onDelete { offsets in
                        let removed = offsets.map { store.profiles[$0] }
                        for profile in removed { store.delete(profile) }
                    }
                    Button("استيراد ملف provisioning") { showImporter = true }
                }
                if let error { Text(error).font(.footnote).foregroundColor(.red) }
            }.listStyle(InsetGroupedListStyle()).navigationTitle("ملف التوقيع")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
                .sheet(isPresented: $showImporter) {
                    ForgeDocumentPicker { urls in
                        showImporter = false
                        guard let url = urls.first else { return }
                        guard url.pathExtension.lowercased() == "mobileprovision" else { error = "اختَر ملفًا بامتداد mobileprovision."; return }
                        switch store.importProfile(from: url) {
                        case .success: error = nil
                        case .failure: error = "تعذر استيراد الملف. تأكد أنه ملف provisioning صالح وموجود على الجهاز."
                        }
                    } onCancel: { showImporter = false }
                }
        }.navigationViewStyle(StackNavigationViewStyle())
    }
}

