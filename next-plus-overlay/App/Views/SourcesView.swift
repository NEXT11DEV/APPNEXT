import SwiftUI

/// Source management uses navigation and forms supported by iOS 15.
struct SourcesView: View {
    @EnvironmentObject private var store: RepositoryStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("إضافة مصدر")) {
                    TextField("https://…/source.json", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
                    Button("إضافة المصدر") { add() }
                        .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let error { Text(error).font(.footnote).foregroundColor(.red) }
                }
                Section(header: Text("مصادر التطبيقات"), footer: Text("تطبيقات المصادر تظهر في تبويب المتجر. اسحب المصدر لحذفه.")) {
                    ForEach(store.visibleRepositories) { repository in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                Text(repository.name).font(.headline)
                                Spacer()
                                if store.loadingRepoID == repository.id { ProgressView() }
                                else { Button { Task { await store.refresh(repository) } } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.borderless) }
                            }
                            Text(repository.url.absoluteString).font(.caption).foregroundColor(.secondary)
                                .textSelection(.enabled).environment(\.layoutDirection, .leftToRight)
                            if let source = store.catalog[repository.id] {
                                Text("\(source.apps.count) تطبيق").font(.caption).foregroundColor(.secondary)
                            }
                            if let message = store.fetchError[repository.id] { Text(message).font(.caption).foregroundColor(.orange) }
                        }.padding(.vertical, 6)
                    }.onDelete { offsets in
                        let removed = offsets.map { store.visibleRepositories[$0] }
                        for repository in removed { store.remove(repository) }
                    }
                }
            }
            .listStyle(InsetGroupedListStyle()).navigationTitle("مصادر التطبيقات")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { dismiss() } } }
        }.navigationViewStyle(StackNavigationViewStyle())
    }

    private func add() {
        switch store.add(urlString: address) {
        case .success(let repository):
            address = ""; error = nil
            Task { await store.refresh(repository) }
        case .failure(let problem):
            switch problem {
            case .invalidURL: error = "أدخل رابط مصدر صالحًا يبدأ بـ https:// أو http://."
            case .duplicate: error = "هذا المصدر مضاف بالفعل."
            }
        }
    }
}

