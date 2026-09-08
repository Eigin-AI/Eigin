import SwiftUI

/// One row of a settings list, data-driven so it can be composed from a
/// simple value. Ported from the web design system's `Row`: adding, deferring
/// and removing are the same row in another tone, not components of their own.
struct AppRowSpec: Identifiable {
    enum Accessory {
        /// Standard disclosure: functional/chevron/right.
        case chevron
        /// Leads out of the app (a browser or a console): functional/arrow/up_right.
        case link
        case plus
        case trash
        case none
    }

    enum Tone {
        /// The settled default.
        case standard
        /// The one thing you might be hunting for, like an add row.
        case accent
        /// Defers — a "show all", a "how it works".
        case muted
        /// Removes: keeps its red to the glyph and never the label.
        case destructive
    }

    /// Controls that replace the accessory outright.
    enum Trailing {
        /// A model that either reaches the agent tab or does not.
        case toggle(isOn: Bool, isDisabled: Bool, action: () -> Void)
        /// State shown in place of the chevron — status is a control here.
        case status(ConnectionState, String)
        /// Escape hatch for one-off controls (a price pill, say).
        case custom(AnyView)
    }

    /// Groups feed this straight into `ForEach`, so two rows that share an
    /// id collide; the default takes the title, so give alike-titled rows
    /// explicit ids.
    var id: String
    var title: String
    var description: String?
    var value: String?
    /// A custom whole-glyph view (a brand avatar, say), taking precedence
    /// over the icon/letter stand-ins.
    var mark: AnyView?
    var icon: Image?
    /// Initials standing in for a missing logo, as an `AppMark`.
    var letter: String?
    var iconSize: CGFloat
    var accessory: Accessory
    var tone: Tone
    var action: (() -> Void)?
    var trailing: Trailing?

    init(
        id: String? = nil,
        title: String,
        description: String? = nil,
        value: String? = nil,
        mark: AnyView? = nil,
        icon: Image? = nil,
        letter: String? = nil,
        iconSize: CGFloat = 32,
        accessory: Accessory = .chevron,
        tone: Tone = .standard,
        action: (() -> Void)? = nil,
        trailing: Trailing? = nil
    ) {
        self.id = id ?? title
        self.title = title
        self.description = description
        self.value = value
        self.mark = mark
        self.icon = icon
        self.letter = letter
        self.iconSize = iconSize
        self.accessory = accessory
        self.tone = tone
        self.action = action
        self.trailing = trailing
    }
}

/// Renders one `AppRowSpec`. Usually composed inside an `AppContentGroup`,
/// which supplies the hairlines between rows; the row itself draws none.
struct AppRow: View {
    let spec: AppRowSpec

    @Environment(\.colors) private var colors
    @State private var isPressed = false

    init(_ spec: AppRowSpec) {
        self.spec = spec
    }

    var body: some View {
        if let action = spec.action, spec.trailing == nil {
            // Only rows without a trailing control get row-level taps: the
            // control next to the title is its own target.
            Button(action: action) { layout }
                .buttonStyle(PressFadeStyle(isPressed: $isPressed))
        } else {
            layout
        }
    }

    private var layout: some View {
        HStack(spacing: Spacing.n16) {
            if let mark = spec.mark {
                mark
                    .frame(width: spec.iconSize, height: spec.iconSize)
            } else if let icon = spec.icon {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
                    .foregroundStyle(colors.icon.standard.base)
                    .frame(width: spec.iconSize, height: spec.iconSize)
            } else if let letter = spec.letter {
                AppMark(letter: letter, size: 32)
                    .frame(width: spec.iconSize, height: spec.iconSize)
            }

            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(spec.title)
                    .typography(Typography.titleXS)
                    .foregroundStyle(titleColor)
                if let description = spec.description {
                    Text(description)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }

            Spacer(minLength: Spacing.n8)

            if let trailing = spec.trailing {
                TrailingControl(trailing: trailing)
            } else {
                if !isValueEmpty {
                    Text(spec.value!)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.trailing)
                }
                accessoryIcon
            }
        }
        .padding(.vertical, Spacing.n16)
        .padding(.horizontal, Spacing.n24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var isValueEmpty: Bool {
        (spec.value ?? "").isEmpty
    }

    private var titleColor: Color {
        switch spec.tone {
        case .standard, .destructive: colors.text.standard.base
        case .accent: colors.accent
        case .muted: colors.text.standard.muted
        }
    }

    private var accessoryColor: Color {
        switch spec.tone {
        case .accent: colors.accent
        case .destructive: colors.text.standard.error
        default: colors.text.standard.muted
        }
    }

    @ViewBuilder
    private var accessoryIcon: some View {
        let size: CGFloat = 16
        switch spec.accessory {
        case .chevron:
            glyph(Iconography.Functional.Chevron.right, size: size)
        case .link:
            glyph(Iconography.Functional.Arrow.upRight, size: size)
        case .plus:
            glyph(Iconography.Functional.plus, size: size)
        case .trash:
            glyph(Iconography.Functional.trash, size: size)
        case .none:
            EmptyView()
        }
    }

    private func glyph(_ image: Image, size: CGFloat) -> some View {
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .foregroundStyle(accessoryColor)
    }
}

/// The control that replaces the accessory outright.
private struct TrailingControl: View {
    let trailing: AppRowSpec.Trailing

    var body: some View {
        switch trailing {
        case .status(let state, let label):
            AppStatusLine(state: state, label: label)
        case .toggle(let isOn, let isDisabled, let action):
            if isDisabled {
                AppSwitch(isOn: isOn, variant: .positive, action: action).disabled(true)
            } else {
                AppSwitch(isOn: isOn, variant: .positive, action: action)
            }
        case .custom(let view):
            view
        }
    }
}

/// Fades like a pressable surface; shared by tappable rows.
struct PressFadeStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.5 : 1)
            .onChange(of: configuration.isPressed) { _, pressed in isPressed = pressed }
    }
}

// MARK: - Preview

private struct AppRowPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n24) {
            AppRow(AppRowSpec(title: "Google", description: "Mail, calendar and contacts"))
            AppRow(
                AppRowSpec(
                    title: "Google",
                    description: "Mail, calendar and contacts",
                    trailing: .status(.attention, "Reconnect")
                )
            )
            AppRow(AppRowSpec(title: "Add provider", accessory: .plus, tone: .accent))
            AppRow(AppRowSpec(title: "How it works", tone: .muted))
            AppRow(AppRowSpec(title: "Remove Anthropic", accessory: .trash, tone: .destructive))
            AppRow(AppRowSpec(title: "Credits", value: "480", accessory: .none))
            AppRow(
                AppRowSpec(
                    title: "Claude Sonnet 4.6",
                    trailing: .toggle(isOn: true, isDisabled: false, action: {})
                )
            )
        }
        .padding(Spacing.n24)
        .background(colors.surface.standard.base)
    }

    @Environment(\.colors) private var colors
}

#Preview("Light") {
    AppRowPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppRowPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
