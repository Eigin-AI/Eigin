import SwiftUI

struct AppSubtleActionButton: View {
    let label: String
    let icon: Image
    let size: AppButtonSize
    let action: () -> Void

    init(
        _ label: String,
        icon: Image,
        size: AppButtonSize = .large,
        action: @escaping () -> Void
    ) {
        self.label = label
        self.icon = icon
        self.size = size
        self.action = action
    }

    @Environment(\.colors) private var colors

    var body: some View {
        AppButton(label, variant: .secondary, size: size, action: action) {
            icon
                .foregroundStyle(colors.icon.standard.base)
        }
    }
}

#Preview("Large") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSubtleActionButton("Action", icon: Image(systemName: "plus")) {}
            AppSubtleActionButton("Disabled", icon: Image(systemName: "plus")) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}

#Preview("Medium") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSubtleActionButton("Action", icon: Image(systemName: "plus"), size: .medium) {}
            AppSubtleActionButton("Disabled", icon: Image(systemName: "plus"), size: .medium) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}

#Preview("Small") {
    ButtonPreview {
        VStack(spacing: Spacing.n16) {
            AppSubtleActionButton("Action", icon: Image(systemName: "plus"), size: .small) {}
            AppSubtleActionButton("Disabled", icon: Image(systemName: "plus"), size: .small) {}
                .disabled(true)
        }
    }
    .resolveTheme()
}
