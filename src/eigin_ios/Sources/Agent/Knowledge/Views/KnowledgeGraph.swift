import SwiftUI

/// Interactive force-directed graph visualization for the knowledge base.
///
/// Renders nodes and edges on a `Canvas`, with transparent overlay rectangles
/// for tap targets. Supports pinch-to-zoom, drag-to-pan, and tap-to-navigate.
/// The center (focus) node is largest, hop-1 neighbors are smaller, and hop-2
/// nodes are smallest and faintest.
struct KnowledgeGraph: View {
    @Environment(\.colors) private var colors

    @Bindable var viewModel: KnowledgeGraphViewModel
    let agentID: UUID?

    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastDragOffset: CGSize = .zero
    @State private var panVelocity: CGSize = .zero
    @State private var momentumTimer: Timer?
    @State private var detailEntity: DetailItem?
    @State private var searchText = ""

    var body: some View {
        ZStack {
            colors.background.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.nodes.isEmpty {
                ContentUnavailableView(
                    "No Knowledge",
                    systemImage: "book.closed",
                    description: Text(Localized.Knowledge.EmptyState.hint)
                )
            } else {
                graphCanvas
                    .gesture(dragGesture)
                    .gesture(magnificationGesture)

                tapTargets

                VStack {
                    searchBar
                    Spacer()
                }
            }
        }
        .sheet(item: $detailEntity) { item in
            NavigationStack {
                FactDetail(
                    entity: item.entity,
                    isBundled: FactsListHelpers.isBundled(item.entity),
                    agentID: agentID,
                    onDelete: { deletedID in
                        detailEntity = nil
                        Task { await viewModel.handleEntityDeleted(id: deletedID) }
                    }
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { detailEntity = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Canvas

    private var graphCanvas: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            Canvas { context, _ in
                // Draw edges first (behind nodes).
                for edge in viewModel.edges {
                    guard let source = viewModel.nodes.first(where: { $0.id == edge.sourceID }),
                          let target = viewModel.nodes.first(where: { $0.id == edge.targetID })
                    else { continue }

                    let from = transformedPoint(source.position, center: center)
                    let to = transformedPoint(target.position, center: center)

                    let maxHop = max(source.hop, target.hop)
                    let edgeOpacity = maxHop >= 2 ? GraphConfig.hop2EdgeOpacity : GraphConfig
                        .hop1EdgeOpacity
                    let lineWidth = maxHop >= 2 ? GraphConfig.hop2EdgeWidth : GraphConfig
                        .hop1EdgeWidth

                    var path = Path()
                    path.move(to: from)
                    path.addLine(to: to)
                    context.stroke(
                        path,
                        with: .color(colors.border.opacity(edgeOpacity)),
                        lineWidth: lineWidth
                    )
                }

                // Draw nodes (hop-2 first so focus/hop-1 draw on top).
                let sorted = viewModel.nodes.sorted { $0.hop > $1.hop }
                for node in sorted {
                    let pos = transformedPoint(node.position, center: center)
                    drawNode(node, at: pos, in: &context)
                }
            }
        }
    }

    // MARK: - Node Drawing

    private func nodeSize(for node: GraphNode) -> CGFloat {
        node.displaySize * scale
    }

    private func nodeOpacity(for node: GraphNode) -> Double {
        switch node.hop {
        case 0: GraphConfig.focusNodeOpacity
        case 1: GraphConfig.hop1NodeOpacity
        default: GraphConfig.hop2NodeOpacity
        }
    }

    private func drawNode(_ node: GraphNode, at pos: CGPoint, in context: inout GraphicsContext) {
        let appear = node.appearScale
        guard appear > 0.01 else { return }

        let size = nodeSize(for: node) * appear
        let rect = CGRect(x: pos.x - size / 2, y: pos.y - size / 2, width: size, height: size)
        let opacity = nodeOpacity(for: node) * Double(appear)

        // All nodes are circles with accent fill.
        let path = Path(ellipseIn: rect)
        context.fill(path, with: .color(colors.accent.opacity(opacity)))

        // White icon inside (rendered as resolved Text for correct tinting).
        let iconFontSize = size * GraphConfig.iconSizeRatio
        if appear > GraphConfig.iconAppearThreshold, iconFontSize >= 1 {
            let icon = nodeIcon(for: node.entityType)
            let iconOpacity: Double = (node.hop == 2 ? GraphConfig.hop2IconOpacity : 1.0) *
                Double(appear)
            let resolvedIcon = context.resolve(
                Text(Image(systemName: icon))
                    .font(.system(size: iconFontSize))
                    .foregroundStyle(.white.opacity(iconOpacity))
            )
            context.draw(resolvedIcon, at: pos, anchor: .center)
        }

        // Label below node — visibility is a continuous 0→1 score based on:
        // 1. Appear animation progress
        // 2. Node size relative to minimum (zoom-dependent)
        // 3. How crowded the neighborhood is (zoom-adjusted)
        // Focus node always gets full visibility.
        let labelVisibility: Double
        if node.hop == 0 {
            labelVisibility = Double(appear)
        } else {
            // Size factor: 0 below labelMinNodeSize, quickly ramps to 1 just above it.
            let minSize = GraphConfig.labelMinNodeSize
            let sizeFactor = Double(max(0, min(1, (size - minSize * 0.8) / (minSize * 0.3))))

            // Crowding factor: 1 when few neighbors, fading to 0 as it gets dense.
            // Zoom scales the tolerance — zoomed in = more tolerant.
            let crowdingBudget = Double(GraphConfig.labelCrowdingThreshold) + Double(scale) * 4.0
            let crowdingFactor = max(
                0,
                min(1, 1.0 - Double(node.nearbyCount) / (crowdingBudget * 2.0))
            )

            labelVisibility = Double(appear) * sizeFactor * crowdingFactor
        }

        if labelVisibility > 0.05 {
            let maxLabelLen = node.hop == 0 ? GraphConfig.focusLabelMaxLength
                : (node.hop == 1 ? GraphConfig.hop1LabelMaxLength : GraphConfig.hop2LabelMaxLength)
            let displayName = node.displayName.count > maxLabelLen
                ? String(node.displayName.prefix(maxLabelLen - 2)) + "..."
                : node.displayName
            let labelFont: Font = node.hop <= 1 ? Typography.caption.font : .system(.caption2)
            let labelColor: Color = node.hop == 0 ? colors.textPrimary :
                (node.hop == 1 ? colors.textSecondary : colors.textTertiary)
            let label = context.resolve(
                Text(displayName).font(labelFont)
                    .foregroundStyle(labelColor.opacity(labelVisibility))
            )
            context.draw(
                label,
                at: CGPoint(x: pos.x, y: pos.y + size / 2 + 4 * scale),
                anchor: .top
            )
        }
    }

    // MARK: - Tap Targets

    private var tapTargets: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ForEach(viewModel.nodes) { node in
                let pos = transformedPoint(node.position, center: center)
                let size = nodeSize(for: node) + 16 * scale

                Color.clear
                    .frame(width: size, height: size)
                    .contentShape(Rectangle())
                    .position(pos)
                    .onTapGesture {
                        handleNodeTap(node)
                    }
            }
        }
    }

    // MARK: - Search

    private var searchBar: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.textSecondary)
            TextField("Search knowledge...", text: $searchText)
                .typography(Typography.body)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(colors.textTertiary)
                }
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.md)
        .padding(.top, Spacing.sm)
        .onChange(of: searchText) {
            Task { await viewModel.search(query: searchText) }
        }
        .overlay(alignment: .top) {
            if !viewModel.searchResults.isEmpty {
                searchResultsList
                    .padding(.top, 48)
            }
        }
    }

    private var searchResultsList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.searchResults.prefix(8)) { node in
                Button {
                    searchText = ""
                    viewModel.clearSearch()
                    Task { await viewModel.focusOn(entityID: node.id) }
                    resetViewport()
                } label: {
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: nodeIcon(for: node.entityType))
                            .foregroundStyle(colors.accent)
                            .frame(width: 24)
                        Text(node.displayName)
                            .typography(Typography.body)
                            .foregroundStyle(colors.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(node.entityType)
                            .typography(Typography.caption)
                            .foregroundStyle(colors.textSecondary)
                    }
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, Spacing.sm)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Gestures

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                momentumTimer?.invalidate()
                momentumTimer = nil
                offset = CGSize(
                    width: lastDragOffset.width + value.translation.width,
                    height: lastDragOffset.height + value.translation.height
                )
            }
            .onEnded { value in
                lastDragOffset = offset
                // Kick off momentum from the predicted velocity.
                panVelocity = CGSize(
                    width: (value.predictedEndTranslation.width - value.translation.width) / 0.4,
                    height: (value.predictedEndTranslation.height - value.translation.height) / 0.4
                )
                startMomentum()
            }
    }

    private func startMomentum() {
        momentumTimer?.invalidate()
        let interval: TimeInterval = 1.0 / 60.0
        momentumTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            MainActor.assumeIsolated {
                let vx = panVelocity.width
                let vy = panVelocity.height
                guard abs(vx) > 0.5 || abs(vy) > 0.5 else {
                    momentumTimer?.invalidate()
                    momentumTimer = nil
                    return
                }
                offset = CGSize(
                    width: offset.width + vx * interval,
                    height: offset.height + vy * interval
                )
                lastDragOffset = offset
                panVelocity = CGSize(
                    width: vx * 0.95,
                    height: vy * 0.95
                )
            }
        }
    }

    private var magnificationGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = max(0.3, min(3.0, baseScale * value.magnification))
                // Adjust offset so the screen center stays fixed while zooming.
                let ratio = newScale / scale
                offset = CGSize(
                    width: offset.width * ratio,
                    height: offset.height * ratio
                )
                lastDragOffset = offset
                scale = newScale
            }
            .onEnded { value in
                baseScale = max(0.3, min(3.0, baseScale * value.magnification))
            }
    }

    // MARK: - Coordinate Transform

    private func transformedPoint(_ point: CGPoint, center: CGPoint) -> CGPoint {
        CGPoint(
            x: center.x + point.x * scale + offset.width,
            y: center.y + point.y * scale + offset.height
        )
    }

    // MARK: - Actions

    private func handleNodeTap(_ node: GraphNode) {
        if node.hop == 0 {
            Task {
                if let entity = await viewModel.getEntity(id: node.id) {
                    detailEntity = DetailItem(entity: entity)
                }
            }
        } else {
            Task {
                await viewModel.focusOn(entityID: node.id)
            }
        }
    }

    private func resetViewport() {
        offset = .zero
        lastDragOffset = .zero
    }

    // MARK: - Detail Item

    /// Wrapper to make `FirmEntity` usable with `sheet(item:)`.
    struct DetailItem: Identifiable {
        let id: String
        let entity: FirmEntity
        init(entity: FirmEntity) {
            id = entity.id
            self.entity = entity
        }
    }

    // MARK: - Node Appearance

    private func nodeIcon(for entityType: String) -> String {
        switch entityType {
        case "actor": "person.fill"
        case "thing": "cube.fill"
        case "fact": "checkmark.seal.fill"
        case "output": "doc.text.fill"
        case "note": "note.text"
        default: "circle.fill"
        }
    }
}

// MARK: - Helpers accessible to other views

/// Shared helpers for facts list / graph interop.
/// Promoted from FactsList private scope so KnowledgeGraph can reuse them.
enum FactsListHelpers {
    static func primaryField(for entity: FirmEntity) -> String {
        for fieldName in ["name", "claim", "content"] {
            if let field = entity.fields.first(where: { $0.name == fieldName }),
               case .string(let value) = field.value,
               !value.isEmpty
            {
                return value.count > 80 ? String(value.prefix(80)) + "..." : value
            }
        }
        return entity.id
    }

    static func createdAt(for entity: FirmEntity) -> Date? {
        guard let field = entity.fields.first(where: { $0.name == "created_at" }),
              case .dateTime(let value) = field.value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.date(from: value)
    }

    static func isBundled(_ entity: FirmEntity) -> Bool {
        let shortID = extractShortID(from: entity.id, type: entity.entityType)
        let bundledPath = BundledKnowledge.entityPath(
            prefix: BundledKnowledge.bundledPrefix,
            type: entity.entityType,
            id: shortID
        )
        return BundledKnowledge.allSources.contains { $0.path == bundledPath }
    }

    static func extractShortID(from qualifiedID: String, type: String) -> String {
        let prefix = type + "."
        return qualifiedID
            .hasPrefix(prefix) ? String(qualifiedID.dropFirst(prefix.count)) : qualifiedID
    }
}

#Preview {
    KnowledgeGraph(
        viewModel: KnowledgeGraphViewModel(
            knowledgeService: PreviewKnowledgeService(),
            agentID: nil
        ),
        agentID: nil
    )
    .previewEnvironment()
}
