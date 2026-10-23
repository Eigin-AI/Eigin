import Factory
import SwiftUI

/// Full stored knowledge, its additional fields, tags, and named relationships.
struct FactDetail: View {
    @Injected(\.knowledgeService) private var knowledgeService
    @Environment(\.dismiss) private var dismiss

    let entity: FirmEntity
    let isBundled: Bool
    let agentID: UUID?
    var onDelete: ((String) -> Void)?

    @State private var details: KnowledgeDetails?
    @State private var showDeleteConfirmation = false
    @State private var showDeleteError = false

    private var presentation: KnowledgePresentation {
        KnowledgePresentation(entity)
    }

    private var tags: [String] {
        guard case .list(let items) = entity.fields.first(where: { $0.name == "tags" })?.value
        else { return [] }
        return items.compactMap {
            guard case .string(let value) = $0 else { return nil }
            return value
        }
    }

    var body: some View {
        AppSecondaryScreen(title: Localized.Knowledge.sectionTitle) {
            AppContentGroup(
                label: KnowledgeLabels.typeName(entity.entityType)
            ) {
                AppRow(AppRowSpec(title: presentation.name, accessory: .none))
                if let content = presentation.content {
                    RowHairline()
                    AppDetailText(text: content)
                }
            }
            if !fieldRows.isEmpty {
                AppRowsGroup(label: Localized.Fact.Detail.Section.fields, rows: fieldRows)
            }
            if !tags.isEmpty {
                AppContentGroup(label: Localized.Fact.Detail.Section.tags) {
                    AppDetailText(text: tags.joined(separator: " · "))
                }
            }
            if let details, !details.relationships.isEmpty {
                AppContentGroup(label: Localized.Fact.Detail.Section.relationships) {
                    ForEach(
                        Array(details.relationships.enumerated()),
                        id: \.element.id
                    ) { index, relationship in
                        if index > 0 { RowHairline() }
                        NavigationLink {
                            FactDetail(
                                entity: relationship.entity,
                                isBundled: KnowledgePresentation
                                    .isBundled(relationship.entity),
                                agentID: agentID,
                                onDelete: onDelete
                            )
                            .hidesTabBar()
                        } label: {
                            AppRow(AppRowSpec(
                                title: KnowledgePresentation(relationship.entity).name,
                                description: KnowledgeLabels.relationshipLabel(relationship)
                            ))
                            .multilineTextAlignment(.leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let details, details.relationshipError != nil {
                AppRowsGroup(label: Localized.Fact.Detail.Section.relationships, rows: [
                    AppRowSpec(
                        title: Localized.Common.Actions.retry,
                        description: Localized.Knowledge.Error.hint,
                        action: { Task { await details.load() } }
                    ),
                ])
            }
            if !isBundled {
                AppRowsGroup(rows: [AppRowSpec(
                    title: Localized.Knowledge.delete,
                    accessory: .trash,
                    tone: .destructive,
                    action: { showDeleteConfirmation = true }
                )])
                .disabled(details == nil || details?.isDeleting == true)
            }
        }
        .task {
            if details == nil { details = KnowledgeDetails(
                entity: entity,
                service: knowledgeService,
                agentID: agentID
            ) }
            await details?.load()
        }
        .alert(Localized.Knowledge.delete, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Knowledge.delete, role: .destructive) {
                Haptics.error()
                Task {
                    if await details?.delete() == true {
                        onDelete?(entity.id)
                        dismiss()
                    } else {
                        showDeleteError = true
                    }
                }
            }
        } message: {
            Text(Localized.Knowledge.deleteWarning)
        }
        .alert(Localized.Knowledge.deleteFailed, isPresented: $showDeleteError) {
            Button(Localized.Common.Actions.ok, role: .cancel) {}
        }
    }

    private var fieldRows: [AppRowSpec] {
        [AppRowSpec(
            id: "entityID",
            title: Localized.Fact.Detail.Label.id,
            description: entity.id,
            accessory: .none
        )] + presentation.fields
            .compactMap { field in
                guard let value = KnowledgeFormatting.value(field.value) else { return nil }
                return AppRowSpec(
                    id: field.name,
                    title: KnowledgeFormatting.label(field.name),
                    description: value,
                    accessory: .none
                )
            }
    }
}

#Preview {
    NavigationStack {
        FactDetail(entity: FirmEntity(id: "thing.eigin", entityType: "thing", fields: [
            FirmField(name: "name", value: .string(value: "Eigin")),
            FirmField(name: "category", value: .enum(value: "digital")),
        ]), isBundled: true, agentID: nil)
    }
    .previewEnvironment()
}
