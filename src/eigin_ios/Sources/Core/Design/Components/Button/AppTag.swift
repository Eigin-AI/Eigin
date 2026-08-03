import SwiftUI

/// A compact capsule for labelling or filtering, with an optional trailing icon.
///
/// Comes in one fixed size and carries the same colours and interaction states
/// as a secondary ``AppButton``.
struct AppTag<Trailing: View>: View {
    let label: String
    let action: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    init(
        _ label: String,
        action: @escaping () -> Void
    ) where Trailing == EmptyView {
        self.label = label
        self.action = action
        trailing = { EmptyView() }
    }

    init(
        _ label: String,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.label = label
        self.action = action
        self.trailing = trailing
    }

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Sizing.Button.Gap.small) {
                Text(label)
                    .typography(Typography.tag)
                trailing()
            }
            .foregroundStyle(colors.text.button.onSecondary)
            .padding(.horizontal, Spacing.n24)
            .frame(height: Sizing.Button.Height.tag)
            .background(colors.button.standard.secondary)
            .overlay {
                Capsule()
                    .fill(isHovered && isEnabled ? colors.interaction.light.hover : .clear)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.full))
        }
        .buttonStyle(AppButtonStyle(variant: .secondary))
        .animation(Animations.smooth, value: isHovered)
        .onHover { isHovered = isEnabled ? $0 : false }
    }
}

// MARK: - Preview

#Preview("Tag") {
    ButtonPreview {
        VStack(alignment: .leading, spacing: Spacing.n16) {
            AppTag("Action text") {}
            AppTag("Action text") {}
                .disabled(true)
            AppTag("Action text", action: {}) {
                Image(systemName: "checkmark")
            }
            AppTag("Family & School", action: {}) {
                Image(systemName: "xmark")
            }
        }
    }
    .resolveTheme()
}
