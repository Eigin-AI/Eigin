import SwiftUI

/// Indeterminate full-area loading with a short statement of what is loading.
struct AppLoadingState: View {
    let title: String

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(spacing: Spacing.n16) {
            SweepRing(size: Spacing.n48, stroke: 3)
            Text(title)
                .typography(Typography.titleS)
                .foregroundStyle(colors.text.standard.base)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}
