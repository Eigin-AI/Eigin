import SwiftUI

/// Content for picking a space to move the current chat into.
///
/// Present with the ``.appSheet`` modifier; this view provides only the
/// scrollable content and header title.
struct SpacePickerSheetContent: View {
    let spaces: [SpaceSnapshot]
    let currentSpaceID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss

    // TODO: if we could make this data-model-independent, we can absorb to design components
    var body: some View {
        VStack(spacing: contentGap) {
            ForEach(spaces) { space in
                AppSelectorButton(
                    "\(space.emoji)  \(space.name)",
                    isSelected: currentSpaceID == space.id
                ) {
                    onSelect(space.id)
                    dismiss()
                }
                .padding(.horizontal, contentPx)
            }
        }
    }
}

private let contentPx = Sizing.PageLayout.ContentGrouping.Px.mobile
private let contentGap = Sizing.PageLayout.ContentGrouping.gap

// MARK: - Preview

#Preview("Space Picker Sheet") {
    SpacePickerSheetPreview()
        .resolveTheme()
}

private struct SpacePickerSheetPreview: View {
    @State private var selectedSpaceID: UUID?
    @Environment(\.colors) private var colors

    private let spaces: [SpaceSnapshot] = [
        SpaceSnapshot(id: UUID(), name: "Work", emoji: "💼", instructions: "Focus"),
        SpaceSnapshot(id: UUID(), name: "Personal", emoji: "🏠", instructions: "Relax"),
    ]

    var body: some View {
        ZStack {
            colors.surface.standard.base.ignoresSafeArea()

            VStack {
                Spacer()
                SpacePickerSheetContent(
                    spaces: spaces,
                    currentSpaceID: selectedSpaceID
                ) { id in
                    selectedSpaceID = id
                }
            }
        }
    }
}
