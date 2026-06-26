import SwiftUI

/// A pill-shaped toggle with a sliding white knob. The track fills with the
/// variant color when on and the control fades when disabled. Follows the
/// codebase's value + action convention: it reflects `isOn` and calls `action`
/// on tap, leaving state to the caller.
struct AppSwitch: View {
    let isOn: Bool
    let variant: AppSwitchVariant
    let action: () -> Void

    init(
        isOn: Bool,
        variant: AppSwitchVariant = .positive,
        action: @escaping () -> Void
    ) {
        self.isOn = isOn
        self.variant = variant
        self.action = action
    }

    @Environment(\.colors) private var colors
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(trackColor)

            Circle()
                .fill(knobColor)
                .frame(width: Sizing.Switch.knob, height: Sizing.Switch.knob)
                .padding(Sizing.Switch.padding)
                .offset(x: isOn ? knobTravel : 0)
        }
        .frame(width: Sizing.Switch.Track.width, height: Sizing.Switch.Track.height)
        .contentShape(Capsule())
        .onTapGesture { if isEnabled { action() } }
        .opacity(isEnabled ? 1 : 0.5)
        .animation(Animations.snap, value: isOn)
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    // MARK: - Layout

    /// Horizontal distance the knob slides between off and on.
    private var knobTravel: CGFloat {
        Sizing.Switch.Track.width - Sizing.Switch.knob - Sizing.Switch.padding * 2
    }

    // MARK: - Colors

    private var trackColor: Color {
        guard isOn else { return colors.input.standard.inactive }
        return switch variant {
        case .positive: colors.interaction.active.fill
        }
    }

    private var knobColor: Color {
        colors.text.button.onSpot
    }
}

// MARK: - Preview

struct SwitchPreview<Content: View>: View {
    @Environment(\.colors) private var colors
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(Spacing.n24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.surface.standard.base)
    }
}

private struct AppSwitchPreview: View {
    @State private var isOn = true

    var body: some View {
        SwitchPreview {
            VStack(alignment: .leading, spacing: Spacing.n24) {
                AppSwitch(isOn: isOn) { isOn.toggle() }
                AppSwitch(isOn: false) {}
                AppSwitch(isOn: true) {}
                    .disabled(true)
                AppSwitch(isOn: false) {}
                    .disabled(true)
            }
        }
    }
}

#Preview("Light") {
    AppSwitchPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppSwitchPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
