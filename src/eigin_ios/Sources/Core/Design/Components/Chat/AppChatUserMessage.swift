import SwiftUI

/// Right-aligned user message bubble with optional collapse behaviour.
///
/// Messages longer than ``collapseThreshold`` characters render collapsed
/// by default and tap to expand.
struct AppChatUserMessage: View {
    let text: String
    private static let collapseThreshold = 200
    private static let collapsedHeight: CGFloat = 110

    @Environment(\.colors) private var colors
    @Environment(\.gridBreakpoint) private var breakpoint
    @State private var isCollapsed: Bool

    init(text: String) {
        self.text = text
        _isCollapsed = State(
            initialValue: text.count > Self.collapseThreshold
        )
    }

    private var isLongMessage: Bool {
        text.count > Self.collapseThreshold
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(text)
                .typography(Typography.chatMessageUser)
                .foregroundStyle(colors.text.standard.base)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(
                    maxWidth: isLongMessage ? .infinity : nil,
                    maxHeight: isCollapsed ? Self.collapsedHeight : nil,
                    alignment: .top
                )
                .clipped()
                .mask(alignment: .top) {
                    VStack(spacing: 0) {
                        Color.black
                        if isLongMessage, isCollapsed {
                            LinearGradient(
                                colors: [.black, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 28)
                        }
                    }
                }
                .padding(Spacing.n24)
                .background(colors.surface.standard.alternative)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card))
                .onTapGesture {
                    guard isLongMessage else { return }
                    Haptics.light()
                    withAnimation(Animations.gentle) {
                        isCollapsed.toggle()
                    }
                }
                .animation(Animations.gentle, value: isCollapsed)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, breakpoint.inner)
        .padding(.trailing, breakpoint.outer)
    }
}

// MARK: - Preview

#Preview("Short text") {
    AppChatUserMessage(text: "Hello!")
        .resolveTheme()
}

#Preview("Long text") {
    AppChatUserMessage(
        text: "This is a much longer message that demonstrates how the bubble grows to accommodate multiple lines of text content inside the user message layout, and when it gets really long it should collapse with a nice gradient fade."
    )
    .resolveTheme()
}
