import SwiftUI

/// A secondary page with grouped content under a floating back header.
struct AppSecondaryScreen<Content: View, Trailing: View>: View {
    let title: String
    var fillsViewport = false
    @ViewBuilder let content: () -> Content
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SoftEdgeScrollView(fillsViewport: fillsViewport) {
            VStack(spacing: Sizing.PageLayout.gap) { content() }
                .frame(maxWidth: .infinity, maxHeight: fillsViewport ? .infinity : nil)
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(title: title, leading: {
                AppActionButton(
                    icon: Iconography.Functional.Arrow.left,
                    variant: .open,
                    size: .medium,
                    action: { dismiss() }
                )
                .accessibilityLabel(Localized.Common.Actions.back)
            }, trailing: trailing)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

extension AppSecondaryScreen where Trailing == EmptyView {
    init(
        title: String,
        fillsViewport: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.fillsViewport = fillsViewport
        self.content = content
        trailing = { EmptyView() }
    }
}
