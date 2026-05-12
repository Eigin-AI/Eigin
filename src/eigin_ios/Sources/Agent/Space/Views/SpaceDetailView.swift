import SwiftData
import SwiftUI

struct SpaceDetailView: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable var space: Space

    @State private var showEmojiPicker = false
    @State private var isEditingName = false
    @State private var editingNameText = ""
    @FocusState private var isNameFocused: Bool
    @State private var showDeleteConfirmation = false

    @Query(sort: \Chat.updatedAt) private var allChats: [Chat]

    var body: some View {
        Form {
            presentationSection
            instructionsSection
            privacySection
            deleteSection
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(
            space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name,
            style: Typography.largeTitle
        )
        .navigationBarTitleDisplayMode(.inline)
        .alert(Localized.Common.Alert.deleteSpaceTitle, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Common.Actions.delete, role: .destructive) {
                Haptics.error()
                deleteSpace()
            }
        } message: {
            Text(Localized.Space.deleteWarning)
        }
    }

    // MARK: - Presentation

    private var presentationSection: some View {
        Section {
            HStack(alignment: .center, spacing: Spacing.sm) {
                Button {
                    showEmojiPicker = true
                } label: {
                    Text(space.emoji)
                        .font(.system(size: 40))
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showEmojiPicker) {
                    EmojiGrid(
                        selectedEmoji: $space.emoji,
                        isPresented: $showEmojiPicker,
                        colors: colors
                    )
                }

                if isEditingName {
                    TextField(Localized.Common.Fields.spaceName, text: $editingNameText)
                        .typography(Typography.title)
                        .focused($isNameFocused)
                        .onSubmit { commitNameEdit() }
                        .onChange(of: isNameFocused) { _, focused in
                            if !focused { commitNameEdit() }
                        }
                        .onAppear {
                            editingNameText = space.name
                            isNameFocused = true
                        }
                } else {
                    Text(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)
                        .typography(Typography.title)
                        .foregroundStyle(colors.textPrimary)
                        .onTapGesture {
                            editingNameText = space.name
                            withAnimation(Animations.snap) {
                                isEditingName = true
                            }
                        }
                }

                Spacer()
            }
            .listRowBackground(colors.surface)
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        Section {
            NavigationLink {
                DocumentEditor(
                    title: Localized.Space.Section.instructions,
                    text: $space.instructions
                )
            } label: {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: "text.alignleft", color: .blue)
                    Text(Localized.Space.Section.instructions)
                        .typography(Typography.subheadline)
                        .foregroundStyle(colors.textPrimary)
                    Spacer()
                    Text(space.instructions
                        .isEmpty ? Localized.Fact.Detail
                        .notSet : String(space.instructions.prefix(30)) +
                        "...")
                        .foregroundStyle(colors.textSecondary)
                        .typography(Typography.callout)
                        .lineLimit(1)
                }
            }
            .listRowBackground(colors.surface)
        } header: {
            Text(Localized.Space.Section.instructions)
                .typography(Typography.label)
        }
    }

    // MARK: - Privacy

    private var privacySection: some View {
        Section {
            Toggle(isOn: $space.isPrivate) {
                HStack(spacing: Spacing.sm) {
                    SettingsIcon(systemName: "eye.slash", color: .purple)
                    VStack(alignment: .leading) {
                        Text(Localized.Space.Detail.Label.private)
                            .typography(Typography.subheadline)
                            .foregroundStyle(colors.textPrimary)
                        Text(Localized.Space.Detail.Hint.private)
                            .typography(Typography.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                }
            }
            .listRowBackground(colors.surface)
        }
    }

    // MARK: - Delete

    private var deleteSection: some View {
        Section {
            Button(Localized.Space.Detail.Action.deleteSpace, role: .destructive) {
                showDeleteConfirmation = true
            }
            .typography(Typography.subheadline)
            .listRowBackground(colors.surface)
        }
    }

    // MARK: - Helpers

    private func commitNameEdit() {
        let trimmed = editingNameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            space.name = trimmed
            space.updatedAt = .now
            Haptics.light()
        }
        withAnimation(Animations.snap) {
            isEditingName = false
        }
    }

    private func deleteSpace() {
        let spaceID = space.id
        for chat in allChats where chat.spaceID == spaceID {
            chat.spaceID = nil
        }
        if let context = space.modelContext {
            let descriptor = FetchDescriptor<FirmSource>(
                predicate: #Predicate { $0.spaceID == spaceID }
            )
            if let sources = try? context.fetch(descriptor) {
                for source in sources {
                    source.spaceID = nil
                }
            }
        }
        modelContext.delete(space)
        dismiss()
    }
}
