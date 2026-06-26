import SwiftUI

struct DocumentEditor: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gridBreakpoint) private var breakpoint

    let title: String
    @Binding var text: String

    var body: some View {
        VStack(spacing: 0) {
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

            TextEditor(text: $text)
                .typography(Typography.chatMessageUser)
                .padding(.horizontal, breakpoint.outer)
                .scrollContentBackground(.hidden)
                .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}
