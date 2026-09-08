import SwiftUI

/// A dot and a word: the canonical statement of a connection's state, as in
/// the web design system. Green is up, amber wants something from you, red is
/// down through no fault of yours, hollow is not in use, and grey is disabled.
struct AppStatusLine: View {
    let state: ConnectionState
    let label: String

    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: Spacing.n8) {
            dot
            Text(label)
                .typography(Typography.tag)
                .foregroundStyle(textColor)
        }
    }

    private var dot: some View {
        Circle()
            .frame(width: 8, height: 8)
            .modifier(DotStyle(state: state, colors: colors))
    }

    private var textColor: Color {
        switch state {
        case .attention, .unavailable: colors.text.standard.base
        case .disabled: colors.text.standard.disabled
        default: colors.text.standard.muted
        }
    }
}

/// Filled dots for the live states, hollow outlines for the resting ones.
private struct DotStyle: ViewModifier {
    let state: ConnectionState
    let colors: ResolvedColors

    func body(content: Content) -> some View {
        switch state {
        case .connected:
            content.foregroundStyle(colors.icon.signal.approve)
        case .attention:
            content.foregroundStyle(colors.icon.signal.notice)
        case .unavailable:
            content.foregroundStyle(colors.icon.signal.negative)
        case .off:
            content
                .foregroundStyle(colors.text.standard.muted)
                .overlay(Circle().strokeBorder(colors.text.standard.muted, lineWidth: 1.5))
        case .disabled:
            content
                .foregroundStyle(.clear)
                .overlay(
                    Circle().strokeBorder(colors.text.standard.disabled, lineWidth: 1.5)
                )
        }
    }
}

// MARK: - Preview

private struct AppStatusLinePreview: View {
    var body: some View {
        VStack(spacing: Spacing.n16) {
            AppStatusLine(state: .connected, label: "Connected")
            AppStatusLine(state: .attention, label: "Reconnect")
            AppStatusLine(state: .unavailable, label: "Unavailable")
            AppStatusLine(state: .off, label: "Not installed")
            AppStatusLine(state: .disabled, label: "Off")
        }
        .padding(Spacing.n24)
        .background(colors0.surface.standard.base)
    }

    @Environment(\.colors) private var colors0
}

#Preview("Light") {
    AppStatusLinePreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppStatusLinePreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
