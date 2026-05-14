import SwiftUI

struct AppButtonStyle: ButtonStyle {
    let variant: AppButtonVariant

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Capsule()
                    .fill(configuration.isPressed ? pressedColor : .clear)
            }
            .overlay {
                Capsule()
                    .fill(!isEnabled ? disabledColor : .clear)
            }
            .animation(Animations.snap, value: configuration.isPressed)
            .animation(Animations.smooth, value: isEnabled)
    }

    private var pressedColor: Color {
        switch variant {
        case .primary, .secondary: colors.interaction.light.pressed
        case .spot, .destructive: colors.interaction.dark.pressed
        case .open: colors.interaction.open.pressed
        }
    }

    private var disabledColor: Color {
        switch variant {
        case .primary, .secondary: colors.interaction.light.disabled
        case .spot, .destructive: colors.interaction.dark.disabled
        case .open: .clear
        }
    }
}
