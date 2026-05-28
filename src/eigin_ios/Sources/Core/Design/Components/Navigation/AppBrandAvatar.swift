import SwiftUI

/// A circular avatar with the brand spot color as background.
///
/// Displays an image centered inside a circle filled with the spot button color.
/// The image is inset so it doesn't touch the circle edge.
struct AppBrandAvatar: View {
    let image: Image
    let size: CGFloat
    let insets: EdgeInsets
    let action: (() -> Void)?

    @Environment(\.colors) private var colors

    init(
        image: Image,
        size: CGFloat = 56,
        insets: EdgeInsets = EdgeInsets(
            top: Spacing.n8,
            leading: Spacing.n8,
            bottom: Spacing.n8,
            trailing: Spacing.n8
        ),
        action: (() -> Void)? = nil
    ) {
        self.image = image
        self.size = size
        self.insets = insets
        self.action = action
    }

    var body: some View {
        let content = image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(colors.text.standard.base)
            .padding(insets)

        if let action {
            Button(action: action) {
                content
                    .frame(width: size, height: size)
                    .background(colors.surface.impact.base)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        } else {
            content
                .frame(width: size, height: size)
                .background(colors.surface.impact.base)
                .clipShape(Circle())
        }
    }
}

// MARK: - Preview

#Preview("Light") {
    BrandAvatarPreview()
        .resolveTheme()
}

#Preview("Dark") {
    BrandAvatarPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

#Preview("Pressable") {
    BrandAvatarPreview(action: {})
        .resolveTheme()
}

private struct BrandAvatarPreview: View {
    @Environment(\.colors) private var colors
    let action: (() -> Void)?

    init(action: (() -> Void)? = nil) {
        self.action = action
    }

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            AppBrandAvatar(image: Image(systemName: "apple.logo"), action: action)
        }
    }
}
