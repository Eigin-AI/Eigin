import SwiftUI

/// The bottom navigation bar container.
///
/// Displays a row of `AppNavigationTab` items separated by spacers, with two
/// background styles: `.clear` blends transparently with the page; `.surface`
/// shows a rounded-top filled surface using the standard background color.
struct AppNavigationBar: View {
    let background: AppNavigationBarBackground
    let tabs: [AppNavigationTab]

    @Environment(\.colors) private var colors

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0 ..< tabs.count, id: \.self) { index in
                if index > 0 {
                    Spacer()
                }
                tabs[index]
            }
        }
        .padding(.top, Spacing.n8)
        .padding(.bottom, Spacing.n24)
        .padding(.horizontal, Spacing.n48)
        .frame(maxWidth: .infinity)
        .background(backgroundShape)
    }

    @ViewBuilder
    private var backgroundShape: some View {
        switch background {
        case .clear:
            Color.clear
        case .surface:
            colors.surface.standard.base
                .clipShape(
                    UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: Radius.card,
                            topTrailing: Radius.card
                        ),
                        style: .continuous
                    )
                )
        }
    }
}

enum AppNavigationBarBackground {
    case clear
    case surface
}

// MARK: - Preview

#Preview("Surface Light") {
    AppNavigationBarPreview(background: .surface)
        .resolveTheme()
}

#Preview("Surface Dark") {
    AppNavigationBarPreview(background: .surface)
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

#Preview("Clear Light") {
    AppNavigationBarPreview(background: .clear)
        .resolveTheme()
}

#Preview("Clear Dark") {
    AppNavigationBarPreview(background: .clear)
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

private struct AppNavigationBarPreview: View {
    let background: AppNavigationBarBackground
    @State private var selected = 0
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()

            VStack {
                Spacer()
                AppNavigationBar(background: background, tabs: [
                    AppNavigationTab(
                        icon: Iconography.Brand.avatar,
                        label: "Eigin",
                        isSelected: selected == 0
                    ) {
                        selected = 0
                    },
                    AppNavigationTab(
                        icon: Iconography.Brand.security,
                        label: "Spaces",
                        isSelected: selected == 1
                    ) {
                        selected = 1
                    },
                    AppNavigationTab(
                        icon: Iconography.Brand.settings,
                        label: "Settings",
                        isSelected: selected == 2
                    ) {
                        selected = 2
                    },
                ])
            }
        }
    }
}
