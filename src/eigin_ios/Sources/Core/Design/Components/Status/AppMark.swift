import SwiftUI

/// A connection's logo, or its initial in a circle where we ship no asset.
/// Layout never depends on whether an asset exists: the circle is always
/// there, and the fallback keeps unmarked services from looking broken.
struct AppMark: View {
    private let icon: Image?
    private let letter: String?
    private let size: CGFloat

    @Environment(\.colors) private var colors

    init(icon: Image? = nil, letter: String? = nil, size: CGFloat = 64) {
        self.icon = icon
        self.letter = letter
        self.size = size
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(colors.surface.standard.elevated)
                .frame(width: size, height: size)

            if let icon {
                icon
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: round(size / 2), height: round(size / 2))
                    .foregroundStyle(colors.icon.standard.base)
            } else if let letter {
                Text(letter)
                    // Sized to the mark, not to the display scale: the same
                    // letter reads correctly at 64 and at 32.
                    .font(.custom("NorthEastCN-Bold", size: round(size / 2)).weight(.bold))
                    .foregroundStyle(colors.text.standard.base)
            }
        }
    }
}

// MARK: - Preview

private struct AppMarkPreview: View {
    var body: some View {
        HStack(spacing: Spacing.n24) {
            AppMark(icon: Iconography.Provider.anthropic)
            AppMark(icon: Iconography.Service.linear, size: 32)
            AppMark(letter: "F")
            AppMark(letter: "R", size: 32)
        }
        .padding(Spacing.n24)
        .background(colors.surface.standard.base)
    }

    @Environment(\.colors) private var colors
}

#Preview("Light") {
    AppMarkPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppMarkPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
