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
        AppSecondaryScreen(title: Localized.Space.Detail.title) {
            AppContentGroup(label: Localized.Space.Detail.identity) {
                presentationCard
                RowHairline()
                NavigationLink {
                    DocumentEditor(
                        title: Localized.Space.Section.instructions,
                        text: $space.instructions
                    )
                    .hidesTabBar()
                } label: {
                    AppRow(AppRowSpec(title: Localized.Space.Section.instructions))
                }
                .buttonStyle(.plain)
            }
            AppRowsGroup(footnote: Localized.Space.Detail.Hint.private, rows: [AppRowSpec(
                title: Localized.Space.Detail.privateSpace,
                trailing: .custom(AnyView(AppSwitch(isOn: space.isPrivate) {
                    space.isPrivate.toggle()
                    space.updatedAt = .now
                    Haptics.light()
                }.accessibilityLabel(Localized.Space.Detail.privateSpace)))
            )])
            AppRowsGroup(rows: [AppRowSpec(
                title: Localized.Space.Detail.Action.deleteSpace,
                accessory: .trash,
                tone: .destructive,
                action: { showDeleteConfirmation = true }
            )])
        }
        .onDisappear { if isEditingName { commitNameEdit() } }
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

    private var presentationCard: some View {
        HStack(alignment: .center, spacing: Spacing.n12) {
            Button {
                showEmojiPicker = true
            } label: {
                Text(space.emoji)
                    .font(.system(size: 40))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localized.Space.Detail.changeSymbol)
            .popover(isPresented: $showEmojiPicker) {
                EmojiGrid(
                    selectedEmoji: $space.emoji,
                    isPresented: $showEmojiPicker,
                    colors: colors
                )
            }

            if isEditingName {
                TextField(Localized.Common.Fields.spaceName, text: $editingNameText)
                    .typography(Typography.titleM)
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
                Button {
                    editingNameText = space.name
                    withAnimation(Animations.snap) { isEditingName = true }
                } label: {
                    Text(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint(Localized.Common.Fields.spaceName)
            }

            Spacer()
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
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

// MARK: - Preview

#Preview("Private") {
    NavigationStack {
        SpaceDetailView(space: {
            let space = Space(agentID: UUID())
            space.name = "42futures"
            space.emoji = "🚀"
            space.instructions =
                "Strategic tech pilots and AI experiments. A space for exploring what's next."
            space.isPrivate = true
            return space
        }())
    }
    .previewEnvironment()
}

#Preview("Empty instructions") {
    NavigationStack {
        SpaceDetailView(space: {
            let space = Space(agentID: UUID())
            space.name = "The Lab"
            space.emoji = "🧪"
            return space
        }())
    }
    .previewEnvironment()
}
