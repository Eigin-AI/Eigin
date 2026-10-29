import SwiftUI

/// A theme that defers to the standard iOS system colors and semantic tokens.
struct SystemTheme: Theme {
    var name: String {
        Localized.Settings.Section.system
    }

    let id = "system"

    func colors(for colorScheme: ColorScheme) -> ResolvedColors {
        let surfaceColors = ResolvedColors.Surface(
            impact: .init(
                alternative: .orange,
                base: .green,
                coral: Color(hex: "#FE6C3B"),
                elevated: Color(red: 0.26, green: 0.40, blue: 0.29),
                subtle: .brown
            ),
            standard: .init(
                alternative: Color(.tertiarySystemGroupedBackground),
                base: Color(.secondarySystemGroupedBackground),
                elevated: Color(.systemBackground)
            )
        )
        switch colorScheme {
        case .light, .dark:
            return ResolvedColors(
                accent: .blue,
                border: .init(
                    signal: .init(approve: .green, negative: .red, notice: .orange),
                    standard: .init(base: Color(.separator))
                ),
                button: .init(
                    destructive: .init(base: .red),
                    impact: .init(
                        primary: Color(.black).opacity(0.5),
                        secondary: Color(.white).opacity(0.5)
                    ),
                    navigation: .init(base: Color(.systemBackground)),
                    spot: .init(base: .green),
                    standard: .init(primary: .orange, secondary: Color(.white).opacity(0.3))
                ),
                code: .init(
                    comment: Color(.secondaryLabel),
                    deleted: .red,
                    function: .blue,
                    inserted: .green,
                    keyword: .purple,
                    link: .blue,
                    number: .orange,
                    plain: Color(.label),
                    string: .red,
                    type: .teal,
                    variable: Color(.label)
                ),
                icon: .init(
                    impact: .init(
                        base: .white,
                        disabled: .white.opacity(0.5),
                        muted: .white.opacity(0.75)
                    ),
                    signal: .init(approve: .green, negative: .red, notice: .orange),
                    standard: .init(
                        base: Color(.label),
                        disabled: Color(.tertiaryLabel),
                        muted: Color(.secondaryLabel)
                    )
                ),
                input: .init(
                    standard: .init(
                        active: Color(.tertiarySystemFill),
                        inactive: Color(.secondarySystemFill)
                    )
                ),
                interaction: .init(
                    active: .init(fill: .green),
                    border: .init(
                        error: .red,
                        focus: Color(.label),
                        hover: Color(.separator)
                    ),
                    dark: .init(
                        disabled: .white.opacity(0.7),
                        hover: .black.opacity(0.3),
                        pressed: .black.opacity(0.5)
                    ),
                    disabled: .white.opacity(0.8),
                    light: .init(
                        disabled: .white.opacity(0.3),
                        hover: .black.opacity(0.06),
                        pressed: .black.opacity(0.12)
                    ),
                    open: .init(
                        hover: .gray.opacity(0.15),
                        pressed: .gray.opacity(0.25)
                    ),
                    tag: .init(
                        selected: Color(.label),
                        unselected: Color(.systemFill)
                    )
                ),
                surface: surfaceColors,
                text: .init(
                    button: .init(
                        disabled: Color(.tertiaryLabel),
                        onPrimary: Color(.label),
                        onSecondary: Color(.label),
                        onSpot: .white
                    ),
                    impact: .init(
                        base: .white,
                        disabled: .white.opacity(0.5),
                        link: .white.opacity(0.8),
                        muted: .white.opacity(0.7)
                    ),
                    standard: .init(
                        base: Color(.label),
                        disabled: Color(.tertiaryLabel),
                        error: .red,
                        link: .blue,
                        muted: Color(.secondaryLabel)
                    )
                )
            )
        @unknown default:
            return colors(for: .light)
        }
    }
}
