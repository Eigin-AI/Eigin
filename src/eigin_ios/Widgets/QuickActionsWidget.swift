import AppIntents
import SwiftUI
import WidgetKit

/// The quick-action widget.
///
/// Small: a 2×2 grid — the Eigin mark (new chat) as a bare brand-colored glyph,
/// then dictation, photo and call as filled buttons.
/// Medium: a faux chat input pill (new chat) above the same four cells in a
/// row, sized so the outermost sit flush with the pill's edges.
struct QuickActionsView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private let smallRows: [[QuickAction]] = [[.logo, .dictation], [.photo, .liveCall]]
    private let mediumActions: [QuickAction] = [.logo, .dictation, .photo, .liveCall]

    /// The widget can't reach the user's theme choice — that lives in the app's
    /// `UserDefaults` — so it resolves the default theme for the current scheme.
    private var colors: ResolvedColors {
        DefaultTheme().colors(for: colorScheme)
    }

    var body: some View {
        content
            .environment(\.colors, colors)
            .containerBackground(for: .widget) {
                colors.surface.standard.base
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            VStack(spacing: Spacing.n12) {
                ForEach(smallRows, id: \.first?.id) { row in
                    HStack(spacing: Spacing.n12) {
                        ForEach(row) { action in
                            QuickActionButton(action: action)
                        }
                    }
                }
            }
            .padding(Spacing.n12)
        default:
            // Cells are sized from the row's width so the gaps fall only
            // between them — the outermost then line up with the pill's edges.
            GeometryReader { proxy in
                let cell = (proxy.size.width - 3 * Spacing.n24) / 4
                VStack(spacing: Spacing.n16) {
                    ChatPill()
                        .frame(height: Metrics.pillHeight)

                    HStack(spacing: Spacing.n24) {
                        ForEach(mediumActions) { action in
                            QuickActionButton(action: action)
                                .frame(width: cell, height: cell)
                        }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(.horizontal, Spacing.n16)
        }
    }
}

/// Widget-only measurements, derived from the app's sizing tokens. A home
/// screen tile is far smaller than a screen, so the widget scales the input bar
/// down rather than reusing `Sizing.Input` directly.
private enum Metrics {
    /// The input bar at widget scale.
    static let pillHeight = Sizing.Button.Action.small
    /// Send button, inset from the pill the way the app's is.
    static let sendDiameter = Sizing.Button.Action.small - Spacing.n4 * 2

    /// Icon extent as a fraction of its circle — the app's ratio, applied to a
    /// diameter that varies by family and device.
    static let iconScale = Sizing.Button.Icon.medium / Sizing.Button.Action.medium
    /// The bare mark has no fill to inset from, so it runs larger — the same
    /// glyph-to-circle ratio `AppBrandAvatar` uses.
    static let markScale = (Sizing.Button.Action.small - Spacing.n8 * 2)
        / Sizing.Button.Action.small
}

/// One action: a filled circle for the icons, a bare brand-colored glyph for
/// the Eigin mark.
private struct QuickActionButton: View {
    let action: QuickAction

    @Environment(\.colors) private var colors

    var body: some View {
        Button(intent: action.intent) {
            Circle()
                .fill(action.isMark ? .clear : colors.button.standard.secondary)
                .overlay { icon }
                .aspectRatio(1, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(action.caption))
    }

    @ViewBuilder
    private var icon: some View {
        if action.isMark {
            BrandMark()
                .scaleEffect(Metrics.markScale)
        } else {
            action.image
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(colors.icon.standard.base)
                .scaleEffect(Metrics.iconScale)
        }
    }
}

/// The Eigin mark, tinted brand primary.
private struct BrandMark: View {
    @Environment(\.colors) private var colors

    var body: some View {
        Iconography.Brand.avatar
            .resizable()
            .renderingMode(.template)
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(colors.surface.impact.base)
    }
}

/// The medium widget's top band: styled like the app's chat input bar —
/// placeholder text and send button — and starts a new chat.
private struct ChatPill: View {
    @Environment(\.colors) private var colors

    var body: some View {
        Button(intent: NewChatIntent()) {
            HStack(spacing: Spacing.n8) {
                Text(String(localized: "widgets.chatPillTitle"))
                    .typography(Typography.chatMessageUser)
                    .foregroundStyle(colors.text.standard.muted)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)

                sendButton
            }
            .padding(.leading, Spacing.n20)
            .padding(.trailing, Spacing.n4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(colors.surface.standard.elevated, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(localized: "widgets.newChat")))
    }

    private var sendButton: some View {
        Circle()
            .fill(colors.button.standard.primary)
            .frame(width: Metrics.sendDiameter, height: Metrics.sendDiameter)
            .overlay {
                Iconography.Functional.Arrow.up
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(colors.text.button.onPrimary)
                    .scaleEffect(Metrics.iconScale)
            }
    }
}

/// What one button launches and how it's drawn.
private struct QuickAction: Identifiable {
    let route: EiginRoute

    static let logo = QuickAction(route: .newChat)
    static let dictation = QuickAction(route: .dictationChat)
    static let photo = QuickAction(route: .photoChat)
    static let liveCall = QuickAction(route: .liveCallChat)

    var id: String {
        route.rawValue
    }

    /// The mark draws as a bare glyph; everything else gets a filled circle.
    var isMark: Bool {
        route == .newChat
    }
}

private extension QuickAction {
    var intent: any AppIntent {
        switch route {
        case .newChat: NewChatIntent()
        case .dictationChat: DictationChatIntent()
        case .liveCallChat: LiveCallChatIntent()
        case .photoChat: PhotoChatIntent()
        case .openApp: OpenEiginIntent()
        }
    }

    /// `camera` has no icon in `design/assets/icons/` yet, so photo falls back
    /// to an SF Symbol.
    var image: Image {
        switch route {
        case .newChat: Iconography.Brand.avatar
        case .dictationChat: Iconography.Functional.microphone
        case .liveCallChat: Iconography.Functional.phone
        case .photoChat: Image(systemName: "camera.fill")
        case .openApp: Iconography.Brand.avatar
        }
    }

    var caption: String {
        switch route {
        case .newChat: String(localized: "widgets.newChat")
        case .dictationChat: String(localized: "widgets.dictation")
        case .liveCallChat: String(localized: "widgets.liveCall")
        case .photoChat: String(localized: "widgets.photo")
        case .openApp: String(localized: "widgets.openApp")
        }
    }
}
