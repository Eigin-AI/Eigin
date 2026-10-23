import SwiftUI

/// Unabridged stored text, preserving paragraphs in detail cards.
struct AppDetailText: View {
    let text: String
    @Environment(\.colors) private var colors

    var body: some View {
        Text(text)
            .typography(Typography.body)
            .foregroundStyle(colors.text.standard.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(.horizontal, Spacing.n24)
            .padding(.vertical, Spacing.n16)
    }
}
