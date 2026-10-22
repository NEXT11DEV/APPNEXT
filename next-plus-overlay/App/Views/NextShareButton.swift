import SwiftUI
import UIKit

/// UIKit sharing keeps IPA export available on iOS 15 (ShareLink requires 16).
struct NextShareButton<Content: View>: View {
    let item: URL
    private let content: Content
    @State private var showingShare = false
    init(item: URL, @ViewBuilder label: () -> Content) {
        self.item = item
        self.content = label()
    }
    var body: some View {
        Button { showingShare = true } label: { content }
            .sheet(isPresented: $showingShare) { NextActivitySheet(item: item) }
    }
}

private struct NextActivitySheet: UIViewControllerRepresentable {
    let item: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [item], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
