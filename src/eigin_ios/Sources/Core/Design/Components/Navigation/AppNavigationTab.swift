import SwiftUI

/// An individual tab item for the bottom navigation bar.
///
/// Displays an icon above a label in a 64×64 centered frame. Active and inactive
/// states use token-based colors. There is no separate pressed state beyond
/// the selection change.
struct AppNavigationTab: View {
    let icon: Image
    let label: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.n8) {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(iconColor)

                Text(label)
                    .typography(Typography.navTab)
                    .foregroundStyle(labelColor)
            }
            .frame(width: 64, height: 64, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors

    private var iconColor: Color {
        isSelected ? colors.icon.standard.base : colors.icon.standard.disabled
    }

    private var labelColor: Color {
        isSelected ? colors.text.standard.base : colors.text.standard.disabled
    }
}

// MARK: - Preview

#Preview("Light") {
    AppNavigationTabPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppNavigationTabPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}

private struct AppNavigationTabPreview: View {
    @State private var isSelected = false
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()
            AppNavigationTab(
                icon: Image(systemName: "bubble.fill"),
                label: "Eigin",
                isSelected: isSelected
            ) {
                isSelected.toggle()
            }
        }
    }
}
