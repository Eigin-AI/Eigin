import SwiftUI

/// A generic card container: arbitrary content laid out on a rounded, elevated
/// surface with consistent interior padding. Unlike `AppCard`, which renders a
/// fixed headline / explainer / image layout, this shell makes no assumptions
/// about its content and is meant to group anything into a card.
///
/// Pass an `action` to make the whole card tappable; without one it is inert.
/// Fills the available width by default.
struct AppCardSurface<Content: View>: View {
    let padding: CGFloat
    let action: (() -> Void)?
    @ViewBuilder let content: () -> Content

    @Environment(\.colors) private var colors

    init(
        padding: CGFloat = Spacing.n24,
        action: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.padding = padding
        self.action = action
        self.content = content
    }

    var body: some View {
        if let action {
            Button(action: action) { surface }
                .buttonStyle(.plain)
        } else {
            surface
        }
    }

    private var surface: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(colors.surface.standard.alternative)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
    }
}

// MARK: - Preview

private struct AppCardSurfacePreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: Spacing.n16) {
            AppCardSurface {
                Text("Any content goes here, with consistent padding.")
                    .typography(Typography.description)
                    .foregroundStyle(colors.text.standard.base)
            }

            AppCardSurface(action: { print("Tapped") }) {
                HStack(spacing: Spacing.n8) {
                    Text("🚀")
                        .font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tappable card")
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text("2 CHATS")
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    Spacer()
                    Iconography.Functional.Arrow.right
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
        .padding(Spacing.n24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colors.surface.standard.base)
    }
}

#Preview("Light") {
    AppCardSurfacePreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppCardSurfacePreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
