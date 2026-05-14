import SwiftUI

struct AppActionButton: View {
    let icon: Image
    let variant: AppButtonVariant
    let size: AppButtonSize
    let action: () -> Void

    init(
        icon: Image,
        variant: AppButtonVariant = .primary,
        size: AppButtonSize = .large,
        action: @escaping () -> Void
    ) {
        self.icon = icon
        self.variant = variant
        self.size = size
        self.action = action
    }

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            icon
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(iconColor)
                .frame(width: iconSize, height: iconSize)
                .frame(width: buttonSize, height: buttonSize)
                .background(backgroundColor)
                .overlay {
                    Circle()
                        .fill(isHovered && isEnabled ? hoverColor : .clear)
                }
                .clipShape(Circle())
        }
        .buttonStyle(AppButtonStyle(variant: variant))
        .animation(Animations.smooth, value: isHovered)
        .onHover { isHovered = isEnabled ? $0 : false }
    }

    // MARK: - Sizing

    private var buttonSize: CGFloat {
        switch size {
        case .large: Sizing.Button.Action.large
        case .medium: Sizing.Button.Action.medium
        case .small: Sizing.Button.Action.small
        }
    }

    private var iconSize: CGFloat {
        switch size {
        case .large: Sizing.Button.Icon.large
        case .medium: Sizing.Button.Icon.medium
        case .small: Sizing.Button.Icon.small
        }
    }

    // MARK: - Colors

    private var backgroundColor: Color {
        switch variant {
        case .primary: colors.button.standard.primary
        case .secondary: colors.button.standard.secondary
        case .spot: colors.button.spot.base
        case .destructive: colors.button.destructive.base
        case .open: .clear
        }
    }

    private var hoverColor: Color {
        switch variant {
        case .primary, .secondary: colors.interaction.light.hover
        case .spot, .destructive: colors.interaction.dark.hover
        case .open: colors.interaction.open.hover
        }
    }

    private var iconColor: Color {
        switch variant {
        case .primary:
            isEnabled ? colors.text.button.onPrimary : colors.icon.impact.disabled
        case .secondary:
            isEnabled ? colors.icon.standard.base : colors.icon.standard.disabled
        case .spot, .destructive:
            isEnabled ? colors.icon.impact.base : colors.icon.impact.disabled
        case .open:
            isEnabled ? colors.button.spot.base : colors.icon.standard.disabled
        }
    }
}

// MARK: - Preview

#Preview("Large") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppActionButton(icon: Image(systemName: "pause.fill")) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .secondary) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .spot) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .destructive) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .open) {}
        }
    }
    .resolveTheme()
}

#Preview("Medium") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppActionButton(icon: Image(systemName: "pause.fill"), size: .medium) {}
            AppActionButton(
                icon: Image(systemName: "pause.fill"),
                variant: .secondary,
                size: .medium
            ) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .spot, size: .medium) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .open, size: .medium) {}
        }
    }
    .resolveTheme()
}

#Preview("Small") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppActionButton(icon: Image(systemName: "pause.fill"), size: .small) {}
            AppActionButton(
                icon: Image(systemName: "pause.fill"),
                variant: .secondary,
                size: .small
            ) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .spot, size: .small) {}
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .open, size: .small) {}
        }
    }
    .resolveTheme()
}

#Preview("Disabled") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppActionButton(icon: Image(systemName: "pause.fill")) {}
                .disabled(true)
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .secondary) {}
                .disabled(true)
            AppActionButton(icon: Image(systemName: "pause.fill"), variant: .spot) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}
