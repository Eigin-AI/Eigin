import SwiftUI

/// Data model for a single action in ``ActionSheet``.
struct ActionItem {
    let label: String
    let icon: Image
    let action: () -> Void
}

/// A list of action buttons for use inside a sheet.
///
/// All text is passed as plain `String` parameters so the component remains
/// locale-agnostic. Wrap with ``appSheet`` or a custom sheet to present.
struct ActionSheetContent: View {
    let actions: [ActionItem]

    var body: some View {
        VStack(spacing: contentGap) {
            ForEach(actions.indices, id: \.self) { index in
                let item = actions[index]
                AppSubtleActionButton(item.label, icon: item.icon) {
                    item.action()
                }
                .padding(.horizontal, contentPx)
            }
        }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

#Preview("Action Sheet") {
    ActionSheetPreview()
        .resolveTheme()
}

private struct ActionSheetPreview: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()

            VStack {
                Spacer()
                ActionSheetContent(
                    actions: [
                        ActionItem(
                            label: "Spaces",
                            icon: Image(systemName: "folder"),
                            action: {}
                        ),
                        ActionItem(
                            label: "Attach Photo",
                            icon: Image(systemName: "photo"),
                            action: {}
                        ),
                    ]
                )
            }
        }
    }
}
