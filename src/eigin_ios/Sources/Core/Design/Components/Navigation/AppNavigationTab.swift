import SwiftUI

/// An individual tab item for the bottom navigation bar.
///
/// Displays an icon above a label in a 64pt-tall centered frame. The width
/// follows the label, from 64pt up to a 128pt ceiling — longer localizations
/// such as "Indstillinger" fit without truncation; anything wider than the
/// ceiling truncates. Active and inactive states use token-based colors.
/// There is no separate pressed state beyond the selection change.
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
                    .lineLimit(1)
            }
            .frame(minWidth: 64, maxWidth: 128)
            .frame(height: 64, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Colors

    private var iconColor: Color {
        isSelected ? colors.icon.standard.base : colors.icon.standard.muted
    }

    private var labelColor: Color {
        isSelected ? colors.text.standard.base : colors.text.standard.muted
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
