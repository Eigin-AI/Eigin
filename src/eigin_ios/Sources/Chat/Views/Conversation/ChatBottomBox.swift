import SwiftUI

/// The translucent box container at the bottom of the chat.
/// Wraps any content with the shared material styling.
struct ChatBottomBox<Content: View>: View {
    @ViewBuilder let content: Content

    @Environment(\.colors) private var colors

    /// TextField single line (~22pt) + Spacing.sm (8pt) + action buttons (40pt)
    private let minContentHeight: CGFloat = 70

    var body: some View {
        content
            .frame(maxWidth: .infinity, minHeight: minContentHeight)
            .padding(Spacing.md)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(colors.textSecondary.opacity(0.2), lineWidth: 0.5)
            )
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xs)
    }
}
