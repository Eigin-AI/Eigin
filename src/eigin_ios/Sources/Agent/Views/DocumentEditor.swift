import SwiftUI

struct DocumentEditor: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gridBreakpoint) private var breakpoint

    let title: String
    @Binding var text: String

    var body: some View {
        // Softened by the header's soft edge as the text scrolls beneath it.
        TextEditor(text: $text)
            .typography(Typography.chatMessageUser)
            .padding(.horizontal, breakpoint.outer)
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .softEdge {
                AppNavigationHeader(
                    title: title,
                    leading: {
                        AppActionButton(
                            icon: Iconography.Functional.Arrow.left,
                            variant: .open,
                            size: .medium,
                            action: { dismiss() }
                        )
                    }
                )
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
    }
}
