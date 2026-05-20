import SwiftUI

/// Left-aligned assistant / brand message.
///
/// Layout-only view that positions any injected content as a brand message.
/// No background bubble; content sits directly in the container.
struct AppChatBrandMessage<Content: View>: View {
    @ViewBuilder let content: () -> Content

    @Environment(\.gridBreakpoint) private var breakpoint

    var body: some View {
        HStack {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, breakpoint.inner)
    }
}

// MARK: - Preview

#Preview("Short text") {
    AppChatBrandMessage {
        Text("Hello, how can I help?")
            .typography(Typography.chatMessage)
    }
    .resolveTheme()
}

#Preview("Long text") {
    AppChatBrandMessage {
        Text(
            "This is a much longer assistant reply that demonstrates how the content flows across multiple lines in the brand message layout without any background bubble."
        )
        .typography(Typography.chatMessage)
    }
    .resolveTheme()
}
