import SwiftUI

/// The bottom navigation bar container.
///
/// Displays a row of `AppNavigationTab` items separated by spacers. It has no
/// surface of its own: it floats over the screen, and the soft edge beneath
/// it softens content scrolling under it.
struct AppNavigationBar: View {
    /// Matches the drawn height: n8 top padding, 64pt tab row, n24 bottom padding.
    static var height: CGFloat {
        Spacing.n8 + 64 + Spacing.n24
    }

    let tabs: [AppNavigationTab]

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
    }
}

// MARK: - Preview

#Preview("Light") {
    AppNavigationBarPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppNavigationBarPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

private struct AppNavigationBarPreview: View {
    @State private var selected = 0
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()

            VStack {
                Spacer()
                AppNavigationBar(tabs: [
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
