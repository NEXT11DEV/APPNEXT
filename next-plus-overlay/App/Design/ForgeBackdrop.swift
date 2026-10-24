import SwiftUI

struct ForgeBackdrop: View {
    var body: some View {
        Color(uiColor: .systemGroupedBackground).ignoresSafeArea().accessibilityHidden(true)
    }
}

