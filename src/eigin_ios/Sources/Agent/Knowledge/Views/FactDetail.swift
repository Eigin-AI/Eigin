import Factory
import SwiftUI

struct FactDetail: View {
    @Environment(\.colors) private var colors
    @Injected(\.knowledgeService) private var knowledgeService
    @Environment(\.dismiss) private var dismiss

    let entity: FirmEntity
    let isBundled: Bool
    let agentID: UUID?
    var onDelete: ((String) -> Void)?

    @State private var incoming: [FirmEntity] = []
    @State private var outgoing: [FirmEntity] = []
    @State private var showDeleteConfirmation = false

    var body: some View {
        List {
            headerSection
            fieldsSection
            tagsSection
            relationshipsSection
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(primaryName, style: Typography.titleXl)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !isBundled {
                ToolbarItem(placement: .destructiveAction) {
                    Button(Localized.Common.Actions.delete, role: .destructive) {
                        showDeleteConfirmation = true
                    }
                }
            }
        }
        .task { await loadRelationships() }
        .alert(Localized.Common.Alert.deleteFactTitle, isPresented: $showDeleteConfirmation) {
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
            Button(Localized.Common.Actions.delete, role: .destructive) {
                Haptics.error()
                Task {
                    let shortID = extractShortID(from: entity.id, type: entity.entityType)
                    try? await knowledgeService.deleteEntity(
                        type: entity.entityType,
                        id: shortID,
                        spaceID: nil,
                        agentID: agentID
                    )
                    onDelete?(entity.id)
                    dismiss()
                }
            }
        } message: {
            Text(Localized.Facts.deleteWarning)
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            LabeledContent(Localized.Fact.Detail.Label.type) {
                Text(localizedTypeName(entity.entityType))
                    .typography(Typography.note)
                    .padding(.horizontal, Spacing.n8)
                    .padding(.vertical, Spacing.n4)
                    .background(colors.surface.standard.base, in: Capsule())
            }
            LabeledContent(Localized.Fact.Detail.Label.id) {
                Text(entity.id)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
            }
            if isBundled {
                LabeledContent(Localized.Fact.Detail.Label.source) {
                    Text(Localized.Model.bundled)
                        .typography(Typography.note)
                        .foregroundStyle(colors.text.standard.disabled)
                }
            }
        }
    }

    private var fieldsSection: some View {
        Section(Localized.Fact.Detail.Section.fields) {
            ForEach(displayFields, id: \.name) { field in
                fieldRow(field)
            }
        }
    }

    @ViewBuilder
    private var tagsSection: some View {
        let tags = extractTags()
        if !tags.isEmpty {
            Section(Localized.Fact.Detail.Section.tags) {
                FlowLayout(spacing: Spacing.n4) {
                    ForEach(tags, id: \.self) { tag in
                        Text(tag)
                            .typography(Typography.miniLabel)
                            .padding(.horizontal, Spacing.n8)
                            .padding(.vertical, Spacing.n4)
                            .background(colors.surface.standard.base, in: Capsule())
                    }
                }
                .listRowInsets(EdgeInsets(
                    top: Spacing.n8,
                    leading: Spacing.n16,
                    bottom: Spacing.n8,
                    trailing: Spacing.n16
                ))
            }
        }
    }

    @ViewBuilder
    private var relationshipsSection: some View {
        if !incoming.isEmpty || !outgoing.isEmpty {
            Section(Localized.Fact.Detail.Section.relationships) {
                if !outgoing.isEmpty {
                    ForEach(outgoing, id: \.id) { related in
                        NavigationLink {
                            FactDetail(
                                entity: related,
                                isBundled: isBundledEntity(related),
                                agentID: agentID
                            )
                            .hidesTabBar()
                        } label: {
                            HStack(spacing: Spacing.n8) {
                                Image(systemName: "arrow.right.circle")
                                    .foregroundStyle(colors.accent)
                                VStack(alignment: .leading) {
                                    Text(relatedPrimaryName(related))
                                        .typography(Typography.titleXS)
                                    Text(localizedTypeName(related.entityType))
                                        .typography(Typography.miniLabel)
                                        .foregroundStyle(colors.text.standard.muted)
                                }
                            }
                        }
                    }
                }
                if !incoming.isEmpty {
                    ForEach(incoming, id: \.id) { related in
                        NavigationLink {
                            FactDetail(
                                entity: related,
                                isBundled: isBundledEntity(related),
                                agentID: agentID
                            )
                            .hidesTabBar()
                        } label: {
                            HStack(spacing: Spacing.n8) {
                                Image(systemName: "arrow.left.circle")
                                    .foregroundStyle(colors.text.standard.muted)
                                VStack(alignment: .leading) {
                                    Text(relatedPrimaryName(related))
                                        .typography(Typography.titleXS)
                                    Text(localizedTypeName(related.entityType))
                                        .typography(Typography.miniLabel)
                                        .foregroundStyle(colors.text.standard.muted)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Field Display

    /// Fields to display, excluding tags (shown separately) and internal relationship fields.
    private var displayFields: [FirmField] {
        let hiddenFields: Set = ["tags", "relates_to", "belongs_to", "uses", "describes"]
        return entity.fields.filter { !hiddenFields.contains($0.name) }
    }

    private func fieldRow(_ field: FirmField) -> some View {
        VStack(alignment: .leading, spacing: Spacing.n4) {
            Text(field.name.replacingOccurrences(of: "_", with: " ").capitalized)
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            Text(fieldValueString(field.value))
                .typography(Typography.body)
                .foregroundStyle(colors.text.standard.base)
        }
        .padding(.vertical, Spacing.n4)
    }

    private func fieldValueString(_ value: FirmFieldValue) -> String {
        switch value {
        case .string(let v): v
        case .integer(let v): "\(v)"
        case .float(let v): "\(v)"
        case .boolean(let v): v ? "Yes" : "No"
        case .enum(let v): v.split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
        case .entityReference(let id): id
        case .fieldReference(let entityId, let fieldId): "\(entityId).\(fieldId)"
        case .currency(let amount, let code): "\(amount) \(code)"
        case .dateTime(let v): Self.friendlyDate(v)
        case .path(let v): v
        case .list(let items): items.map { fieldValueString($0) }.joined(separator: ", ")
        }
    }

    // MARK: - Tags

    private func extractTags() -> [String] {
        guard let field = entity.fields.first(where: { $0.name == "tags" }),
              case .list(let items) = field.value else { return [] }
        return items.compactMap { item in
            if case .string(let v) = item { return v }
            return nil
        }
    }

    // MARK: - Relationships

    private func loadRelationships() async {
        let shortID = extractShortID(from: entity.id, type: entity.entityType)
        incoming = await (try? knowledgeService.getRelated(
            type: entity.entityType,
            id: shortID,
            direction: .incoming,
            spaceID: nil,
            agentID: agentID
        )) ?? []
        outgoing = await (try? knowledgeService.getRelated(
            type: entity.entityType,
            id: shortID,
            direction: .outgoing,
            spaceID: nil,
            agentID: agentID
        )) ?? []
    }

    // MARK: - Helpers

    private var primaryName: String {
        for fieldName in ["name", "claim", "content"] {
            if let field = entity.fields.first(where: { $0.name == fieldName }),
               case .string(let value) = field.value,
               !value.isEmpty
            {
                return value.count > 40 ? String(value.prefix(40)) + "..." : value
            }
        }
        return entity.id
    }

    private func relatedPrimaryName(_ entity: FirmEntity) -> String {
        for fieldName in ["name", "claim", "content"] {
            if let field = entity.fields.first(where: { $0.name == fieldName }),
               case .string(let value) = field.value,
               !value.isEmpty
            {
                return value.count > 60 ? String(value.prefix(60)) + "..." : value
            }
        }
        return entity.id
    }

    private func extractShortID(from qualifiedID: String, type: String) -> String {
        let prefix = type + "."
        return qualifiedID
            .hasPrefix(prefix) ? String(qualifiedID.dropFirst(prefix.count)) : qualifiedID
    }

    private static let localizedTypeNames: [String: String] = [
        "actor": Localized.Facts.Kind.actor,
        "thing": Localized.Facts.Kind.thing,
        "fact": Localized.Facts.Kind.fact,
        "output": Localized.Facts.Kind.output,
    ]

    private func localizedTypeName(_ type: String) -> String {
        Self.localizedTypeNames[type] ?? type.capitalized
    }

    /// Format a datetime string (e.g. "2025-03-11" or ISO 8601) into a readable date.
    private static func friendlyDate(_ raw: String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate]
        if let date = iso.date(from: raw) {
            return date.formatted(date: .long, time: .omitted)
        }
        // Try full ISO 8601 with time.
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) {
            return date.formatted(date: .long, time: .shortened)
        }
        return raw
    }

    private func isBundledEntity(_ entity: FirmEntity) -> Bool {
        let shortID = extractShortID(from: entity.id, type: entity.entityType)
        let bundledPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.bundledPrefix,
            type: entity.entityType,
            id: shortID
        )
        return BundledKnowledge.allSources.contains { $0.path == bundledPath }
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for tag chips.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(
        proposal: ProposedViewSize,
        subviews: Subviews
    ) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
        }

        return (CGSize(width: maxX, height: y + rowHeight), positions)
    }
}

#Preview {
    NavigationStack {
        FactDetail(
            entity: FirmEntity(
                id: "thing.eigin",
                entityType: "thing",
                fields: [
                    FirmField(name: "name", value: .string(value: "Eigin")),
                    FirmField(name: "category", value: .enum(value: "digital")),
                    FirmField(
                        name: "tags",
                        value: .list(items: [.string(value: "app"), .string(value: "ai")])
                    ),
                    FirmField(name: "created_at", value: .dateTime(value: "2025-03-11")),
                ]
            ),
            isBundled: true,
            agentID: nil
        )
    }
    .previewEnvironment()
}
