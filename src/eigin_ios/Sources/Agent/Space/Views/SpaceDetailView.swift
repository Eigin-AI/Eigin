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
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                presentationCard

                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    instructionsCard
                    privacyCard
                }

                AppButton(
                    Localized.Space.Detail.Action.deleteSpace,
                    variant: .destructive,
                    size: .large
                ) {
                    showDeleteConfirmation = true
                }
            }
            .padding(.horizontal, Spacing.n16)
        } header: {
            AppNavigationHeader(
                title: Localized.Space.Detail.title,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
        AppCardSurface {
            HStack(alignment: .center, spacing: Spacing.n12) {
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
                    Text(space.name.isEmpty ? Localized.Space.List.untitledSpace : space.name)
                        .typography(Typography.titleM)
                        .foregroundStyle(colors.text.standard.base)
                        .onTapGesture {
                            editingNameText = space.name
                            withAnimation(Animations.snap) {
                                isEditingName = true
                            }
                        }
                }

                Spacer()
            }
        }
    }

    // MARK: - Instructions

    private var instructionsCard: some View {
        NavigationLink {
            DocumentEditor(
                title: Localized.Space.Section.instructions,
                text: $space.instructions
            )
            .hidesTabBar()
        } label: {
            AppCardSurface {
                HStack(spacing: Spacing.n16) {
                    Iconography.Functional.note
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(colors.text.standard.muted)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Localized.Space.Section.instructions)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(instructionsPreview)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var instructionsPreview: String {
        if space.instructions.isEmpty {
            return Localized.Fact.Detail.notSet
        }
        return String(space.instructions.prefix(30)) + "..."
    }

    // MARK: - Privacy

    private var privacyCard: some View {
        AppCardSurface {
            HStack(spacing: Spacing.n16) {
                Image(systemName: "eye.slash")
                    .font(.system(size: 17))
                    .foregroundStyle(colors.text.standard.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Localized.Space.Detail.Label.private)
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.base)
                    Text(Localized.Space.Detail.Hint.private)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
                Spacer()
                AppSwitch(isOn: space.isPrivate) {
                    space.isPrivate.toggle()
                    space.updatedAt = .now
                    Haptics.light()
                }
            }
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
