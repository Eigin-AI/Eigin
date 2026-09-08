import SwiftUI

/// A capsule search field, as the web design system's `SearchField`: a
/// magnifier, placeholder text, and nothing else — the pill IS the chrome.
struct AppSearchField: View {
    @Binding var text: String
    let placeholder: String

    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: Spacing.n8) {
            Iconography.Functional.search
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 16, height: 16)
                .foregroundStyle(colors.text.standard.muted)
            TextField(placeholder, text: $text)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Sizing.Input.Px.left)
        .frame(height: Sizing.Input.height)
        .background(colors.input.standard.active)
        .clipShape(Capsule())
    }
}

#Preview {
    VStack(spacing: Spacing.n16) {
        AppSearchField(text: .constant(""), placeholder: "Search integrations")
        AppSearchField(text: .constant("Cla"), placeholder: "Search models")
    }
    .padding(Spacing.n24)
    .previewEnvironment()
}
