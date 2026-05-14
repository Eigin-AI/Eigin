import SwiftUI

struct AppCheckboxButton: View {
    let label: String
    let isChecked: Bool
    let variant: AppButtonVariant
    let size: AppButtonSize
    let action: () -> Void

    init(
        _ label: String,
        isChecked: Bool,
        variant: AppButtonVariant = .secondary,
        size: AppButtonSize = .large,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.isChecked = isChecked
        self.variant = variant
        self.size = size
        self.action = action
    }

    var body: some View {
        AppButton(label, variant: variant, size: size, action: action) {
            CheckboxIndicator(isChecked: isChecked)
        }
    }
}

// MARK: - Indicator

private struct CheckboxIndicator: View {
    let isChecked: Bool

    @Environment(\.colors) private var colors

    var body: some View {
        Image(systemName: isChecked ? "checkmark.square" : "square")
            .foregroundStyle(isChecked ? colors.icon.standard.base : colors.icon.standard.muted)
            .animation(Animations.smooth, value: isChecked)
    }
}

// MARK: - Preview

#Preview("Large") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppCheckboxButton("Checked", isChecked: true) {}
            AppCheckboxButton("Unchecked", isChecked: false) {}
            AppCheckboxButton("Disabled", isChecked: true) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}

#Preview("Medium") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppCheckboxButton("Checked", isChecked: true, size: .medium) {}
            AppCheckboxButton("Unchecked", isChecked: false, size: .medium) {}
        }
    }
    .resolveTheme()
}

#Preview("Small") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppCheckboxButton("Checked", isChecked: true, size: .small) {}
            AppCheckboxButton("Unchecked", isChecked: false, size: .small) {}
        }
    }
    .resolveTheme()
}
