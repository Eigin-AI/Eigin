import SwiftUI

struct DocumentEditor: View {
    @Environment(\.colors) private var colors

    let title: String
    @Binding var text: String

    var body: some View {
        TextEditor(text: $text)
            .typography(Typography.body)
            .padding(.horizontal, Spacing.sm)
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(title, style: Typography.largeTitle)
            .navigationBarTitleDisplayMode(.inline)
    }
}
