import SwiftUI

struct DocumentEditor: View {
    @Environment(\.colors) private var colors

    let title: String
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .typography(Typography.body)
            .padding(.horizontal, Spacing.n8)
            .scrollContentBackground(.hidden)
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(title, style: Typography.titleXl)
            .navigationBarTitleDisplayMode(.inline)
    }
}
