import SwiftUI

struct AppSelectorButton: View {
    let label: String
    let isSelected: Bool
    let variant: AppButtonVariant
    let size: AppButtonSize
    let action: () -> Void

    init(
        _ label: String,
        isSelected: Bool,
        variant: AppButtonVariant = .secondary,
        size: AppButtonSize = .large,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isSelected = isSelected
        self.variant = variant
        self.size = size
        self.action = action
    }

    var body: some View {
        AppButton(label, variant: variant, size: size, action: action) {
            SelectorIndicator(isSelected: isSelected)
        }
    }
}

// MARK: - Indicator

private struct SelectorIndicator: View {
    let isSelected: Bool

    @Environment(\.colors) private var colors

    var body: some View {
        Image(systemName: isSelected ? "checkmark" : "circle")
            .foregroundStyle(isSelected ? colors.icon.standard.base : colors.icon.standard.muted)
            .animation(Animations.smooth, value: isSelected)
    }
}

// MARK: - Preview

#Preview("Large") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSelectorButton("Selected", isSelected: true) {}
            AppSelectorButton("Unselected", isSelected: false) {}
            AppSelectorButton("Disabled", isSelected: true) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}

#Preview("Medium") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSelectorButton("Selected", isSelected: true, size: .medium) {}
            AppSelectorButton("Unselected", isSelected: false, size: .medium) {}
        }
    }
    .resolveTheme()
}

#Preview("Small") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSelectorButton("Selected", isSelected: true, size: .small) {}
            AppSelectorButton("Unselected", isSelected: false, size: .small) {}
        }
    }
    .resolveTheme()
}
