import SwiftUI

/// An info, warning or error card. It carries no action of its own: the
/// notice raises the problem, and the screen's primary action answers it.
/// A tap is a shortcut to that same action — pressed, it fades like any
/// other card — which is why the tone never decides the tap.
struct AppNotice: View {
    enum Tone {
        case info
        case warning
        case error
    }

    let tone: Tone
    let title: String
    let bodyText: String
    var action: (() -> Void)?

    @Environment(\.colors) private var colors

    init(tone: Tone, title: String, body: String, action: (() -> Void)? = nil) {
        self.tone = tone
        self.title = title
        bodyText = body
        self.action = action
    }

    var body: some View {
        AppCardSurface(padding: Spacing.n24, action: action) {
            HStack(alignment: .top, spacing: Spacing.n16) {
                glyph
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(glyphColor)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: Spacing.n8) {
                    Text(title)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                    Text(bodyText)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
    }

    private var glyph: Image {
        switch tone {
        case .info: Iconography.Functional.info
        case .warning, .error: Iconography.Functional.warning
        }
    }

    private var glyphColor: Color {
        switch tone {
        case .info: colors.icon.standard.base
        case .warning: colors.icon.signal.notice
        case .error: colors.icon.signal.negative
        }
    }
}

// MARK: - Preview

private struct AppNoticePreview: View {
    var body: some View {
        VStack(spacing: Spacing.n16) {
            AppNotice(tone: .info, title: "Running low", body: "You are close to running out.")
            AppNotice(
                tone: .warning,
                title: "The key stopped working",
                body: "Anthropic rejected it on the last request.",
                action: {}
            )
            AppNotice(
                tone: .error,
                title: "Eigin Relay is unavailable",
                body: "The service is down, or you have lost connection."
            )
        }
        .padding(Spacing.n24)
        .background(colors.surface.standard.base)
    }

    @Environment(\.colors) private var colors
}

#Preview("Light") {
    AppNoticePreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppNoticePreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
