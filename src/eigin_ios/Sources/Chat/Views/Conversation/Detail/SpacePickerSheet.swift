import SwiftUI

/// Sheet for picking a space to move the current chat into.
struct SpacePickerSheet: View {
    let spaces: [SpaceSnapshot]
    let currentSpaceID: UUID?
    let onSelect: (UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(spaces) { space in
                        Button {
                            onSelect(space.id)
                            dismiss()
                        } label: {
                            HStack {
                                Text(verbatim: "\(space.emoji) \(space.name)")
                                    .typography(Typography.subheadline)
                                    .foregroundStyle(colors.textPrimary)
                                Spacer()
                                if currentSpaceID == space.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(colors.accent)
                                }
                            }
                        }
                    }
                    .listRowBackground(colors.surface)
                }
                if currentSpaceID != nil {
                    Section {
                        Button(role: .destructive) {
                            onSelect(nil)
                            dismiss()
                        } label: {
                            Text(Localized.Space.removeFromSpace)
                                .typography(Typography.subheadline)
                        }
                        .listRowBackground(colors.surface)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(colors.background.ignoresSafeArea())
            .navigationTitle(Localized.Debug.moveToSpaceTitle, style: Typography.largeTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localized.Common.Actions.cancel) { dismiss() }
                }
            }
        }
    }
}
