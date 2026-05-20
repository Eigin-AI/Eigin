import SwiftUI

struct AppButton<Trailing: View>: View {
    let label: String
    let variant: AppButtonVariant
    let size: AppButtonSize
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ label: String,
        variant: AppButtonVariant = .primary,
        size: AppButtonSize = .large,
        action: @escaping () -> Void
    ) where Trailing == EmptyView {
        self.label = label
        self.variant = variant
        self.size = size
        self.action = action
        trailing = { EmptyView() }
    }

    init(
        _ label: String,
        variant: AppButtonVariant = .primary,
        size: AppButtonSize = .large,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.label = label
        self.variant = variant
        self.size = size
        self.action = action
        self.trailing = trailing
    }

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: gap) {
                Text(label)
                    .typography(typography)
                    .foregroundStyle(foregroundColor)
                if Trailing.self != EmptyView.self {
                    Spacer()
                    trailing()
                }
            }
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: size == .large ? .infinity : nil)
            .frame(height: variant == .open ? nil : height)
            .background(backgroundColor)
            .overlay {
                Capsule()
                    .fill(isHovered && isEnabled ? hoverColor : .clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        }
        .buttonStyle(AppButtonStyle(variant: variant))
        .animation(Animations.smooth, value: isHovered)
        .onHover { isHovered = isEnabled ? $0 : false }
    }

    // MARK: - Sizing

    private var height: CGFloat {
        switch size {
        case .large: Sizing.Button.Height.large
        case .medium: Sizing.Button.Height.medium
        case .small: Sizing.Button.Height.small
        case .extraSmall: Sizing.Button.Height.extraSmall
        }
    }

    private var gap: CGFloat {
        switch size {
        case .large: Sizing.Button.Gap.large
        case .medium: Sizing.Button.Gap.medium
        case .small: Sizing.Button.Gap.small
        case .extraSmall: Sizing.Button.Gap.extraSmall
        }
    }

    private var horizontalPadding: CGFloat {
        if variant == .open { return 0 }
        return switch size {
        case .large, .medium: Spacing.n40
        case .small, .extraSmall: Spacing.n24
        }
    }

    private var typography: TypographyStyle {
        switch size {
        case .large: Typography.buttonLarge
        case .medium: Typography.button
        case .small, .extraSmall: Typography.buttonSmall
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

    private var foregroundColor: Color {
        switch variant {
        case .primary: isEnabled ? colors.text.button.onPrimary : colors.text.standard.disabled
        case .secondary: colors.text.button.onSecondary
        case .spot, .destructive: colors.text.button.onSpot
        case .open: isEnabled ? colors.button.spot.base : colors.text.standard.disabled
        }
    }
}

// MARK: - Preview

struct ButtonPreview<Content: View>: View {
    @Environment(\.colors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.n24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.surface.standard.base)
    }
}

#Preview("Large") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppButton("Primary") {}
            AppButton("Disabled Primary") {}
                .disabled(true)
            AppButton("Secondary", variant: .secondary) {}
            AppButton("Disabled Secondary", variant: .secondary) {}.disabled(true)
            AppButton("Spot", variant: .spot) {}
            AppButton("Disabled Spot", variant: .spot) {}
                .disabled(true)
            AppButton("Destructive", variant: .destructive) {}
            AppButton("Disabled Destructive", variant: .destructive) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}

#Preview("Medium") {
    ButtonPreview {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            AppButton("Primary", size: .medium) {}
            AppButton("Secondary", variant: .secondary, size: .medium) {}
            AppButton("Spot", variant: .spot, size: .medium) {}
            AppButton("Open", variant: .open, size: .medium) {}
        }
    }
    .resolveTheme()
}

#Preview("Small") {
    ButtonPreview {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            AppButton("Primary", size: .small) {}
            AppButton("Secondary", variant: .secondary, size: .small) {}
            AppButton("Spot", variant: .spot, size: .small) {}
            AppButton("Open", variant: .open, size: .small) {}
        }
    }
    .resolveTheme()
}

#Preview("ExtraSmall") {
    ButtonPreview {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            AppButton("Primary", size: .extraSmall) {}
            AppButton("Secondary", variant: .secondary, size: .extraSmall) {}
            AppButton("Spot", variant: .spot, size: .extraSmall) {}
            AppButton("Open", variant: .open, size: .extraSmall) {}
        }
    }
    .resolveTheme()
}
