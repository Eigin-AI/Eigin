import SwiftUI

/// Random squash-and-stretch applied on every press, so no two presses look the same.
///
/// TODO: This is a placeholder animation added for a bit of playful delight. If we
/// want to keep it, we should define a proper design-system animation style for
/// interactive elements instead of one-off spring transforms.
private struct JellyTransform {
    var x: CGFloat
    var y: CGFloat
    var rotation: Double

    static func random() -> Self {
        Self(
            x: CGFloat.random(in: 1.04 ... 1.10),
            y: CGFloat.random(in: 0.90 ... 0.98),
            rotation: Double.random(in: -8 ... 8)
        )
    }
}

/// A circular avatar with the brand spot color as background.
///
/// Displays an image centered inside a circle filled with the spot button color.
/// The image is inset so it doesn't touch the circle edge.
///
/// Provide an `action` and the icon will jelly-squash with a random
/// rotation and stretch on every press, while the background stays perfectly still.
struct AppBrandAvatar: View {
    let image: Image
    let size: CGFloat
    let insets: EdgeInsets
    let action: (() -> Void)?

    @Environment(\.colors) private var colors
    @State private var isPressed = false
    @State private var jelly = JellyTransform.random()
    @State private var hapticTrigger = UUID()

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
            .scaleEffect(
                x: isPressed ? jelly.x : 1.0,
                y: isPressed ? jelly.y : 1.0
            )
            .rotationEffect(.degrees(isPressed ? jelly.rotation : 0))
            .animation(
                .spring(response: 0.35, dampingFraction: 0.40),
                value: isPressed
            )

        if let action {
            content
                .frame(width: size, height: size)
                .background(colors.surface.impact.base)
                .clipShape(Circle())
                .contentShape(Circle())
                .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: hapticTrigger)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isPressed {
                                jelly = JellyTransform.random()
                                isPressed = true
                            }
                        }
                        .onEnded { _ in
                            isPressed = false
                            hapticTrigger = UUID()
                            action()
                        }
                )
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
