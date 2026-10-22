import SwiftUI

/// The rows of a ``DataCard``: the document as a tree. Every branch is a row
/// you can open, and the shape on screen is the shape of the payload.
///
/// Arrays stop being positions wherever they can — a set of values collapses
/// to one row, a list of matching records becomes a table, and anything else
/// is labelled by what it is rather than by where it sits.
struct DataRows: View {
    /// Values beside their label, or driven to the opposite edge.
    enum Align {
        case inline
        case justified
    }

    let value: DataValue
    var align: Align = .justified
    /// How many levels stand open before anything is touched.
    var openDepth = 0
    /// How many rows of a long list are shown before it asks.
    var preview = 5
    /// How many characters of a long value are shown before it asks.
    var limit = 280

    /// Which branches are open, by path. Nothing is open until it is asked to
    /// be, so the first screen is the shape of the payload rather than its
    /// contents; a path prefixed with `!` closes a branch `openDepth` opened.
    @State private var opened: Set<String> = []
    /// Long lists and long values that have been asked to show everything.
    @State private var expanded: Set<String> = []

    var body: some View {
        if value.isRecord {
            DataLevelRows(
                value: value, align: align, openDepth: openDepth,
                preview: preview, limit: limit,
                path: "", depth: 0,
                opened: $opened, expanded: $expanded
            )
        } else {
            DataNode(
                label: "", item: value,
                path: "", depth: 0,
                align: align, openDepth: openDepth, preview: preview, limit: limit,
                opened: $opened, expanded: $expanded
            )
        }
    }
}

// MARK: - Level

// One level of the tree: the rows of a record or a structured array, plus the
// "Show all" tail a long one carries. Recursion happens through ``DataNode``.

/// Rows are cap-trimmed (`.textStyle`), like web's
/// `text-box: trim-both cap alphabetic`, so the token's 16pt pitch is all
/// visible air.
private let rowPitch = Spacing.n16

/// The mid-air between a miniLabel and the paragraph that sits beneath it.
private let stackedGap = Spacing.n16

private struct DataLevelRows: View {
    let value: DataValue
    let align: DataRows.Align
    let openDepth: Int
    let preview: Int
    let limit: Int
    let path: String
    /// Depth of the rows this level draws (the root's rows are depth 0).
    let depth: Int
    @Binding var opened: Set<String>
    @Binding var expanded: Set<String>

    var body: some View {
        let expandedKey = expandedKey(for: path)
        let flat = !value.hasBranches
        VStack(alignment: .leading, spacing: rowPitch) {
            rows
            if value.count > preview, !expanded.contains(expandedKey) {
                ShowAllButton(count: value.count) {
                    expanded.insert(expandedKey)
                }
                // On a level with carets, the tail stands in the label
                // column: the caret column comes out of its indent, so the
                // rows above and the offer below share a left edge.
                .padding(.leading, flat ? 0 : 12 + Spacing.n4)
            }
        }
        // A level with nothing to open keeps no room for a caret, so its
        // labels start at the level's own edge. A level with branches keeps
        // the caret column, and every label at that level aligns on it
        // whether the row itself opens or not.
        .environment(\.dataRowLayout, DataRowLayout(flat: flat, align: align))
    }

    @ViewBuilder private var rows: some View {
        if value.isRecord {
            recordRows(value.objectEntries)
        } else {
            arrayRows(value.arrayItems)
        }
    }

    @ViewBuilder private func recordRows(_ entries: [DataValue.Entry]) -> some View {
        ForEach(entries.prefix(preview), id: \.key) { entry in
            DataNode(
                label: entry.key, item: entry.value,
                path: childPath(entry.key), depth: depth,
                align: align, openDepth: openDepth, preview: preview, limit: limit,
                opened: $opened, expanded: $expanded
            )
        }
        if expanded.contains(expandedKey(for: path)), entries.count > preview {
            ForEach(entries.dropFirst(preview), id: \.key) { entry in
                DataNode(
                    label: entry.key, item: entry.value,
                    path: childPath(entry.key), depth: depth,
                    align: align, openDepth: openDepth, preview: preview, limit: limit,
                    opened: $opened, expanded: $expanded
                )
                .transition(DataArrive.transition)
            }
        }
    }

    @ViewBuilder private func arrayRows(_ items: [DataValue]) -> some View {
        ForEach(Array(items.enumerated().prefix(preview)), id: \.offset) { index, item in
            itemNode(item, index: index)
        }
        if expanded.contains(expandedKey(for: path)), items.count > preview {
            ForEach(
                Array(items.enumerated().dropFirst(preview)), id: \.offset
            ) { index, item in
                itemNode(item, index: index)
                    .transition(DataArrive.transition)
            }
        }
    }

    @ViewBuilder private func itemNode(_ item: DataValue, index: Int) -> some View {
        let spent = DataFormat.spentKey(item)
        let unspent = item.childKeys(excluding: spent)
        let name = DataFormat.itemLabel(item, index)
        if item.isRecord, unspent.count == 1 {
            // One remaining fact does not earn a branch of its own.
            let only = unspent[0]
            DataNode(
                label: "\(name) · \(DataFormat.label(only))",
                item: item.value(forKey: only) ?? .null,
                path: childPath(String(index)), depth: depth,
                align: align, openDepth: openDepth, preview: preview, limit: limit,
                opened: $opened, expanded: $expanded
            )
        } else {
            DataNode(
                label: name, item: item,
                path: childPath(String(index)), depth: depth,
                align: align, openDepth: openDepth, preview: preview, limit: limit,
                opened: $opened, expanded: $expanded
            )
        }
    }

    private func childPath(_ key: String) -> String {
        path.isEmpty ? key : "\(path).\(key)"
    }

    private func expandedKey(for path: String) -> String {
        path.isEmpty ? ":root" : path
    }
}

// MARK: - Node

/// One node of the tree: a leaf row, a collapsed set of values, or a branch —
/// the chevron row and everything it opens.
private struct DataNode: View {
    let label: String
    let item: DataValue
    let path: String
    let depth: Int
    let align: DataRows.Align
    let openDepth: Int
    let preview: Int
    let limit: Int
    @Binding var opened: Set<String>
    @Binding var expanded: Set<String>

    @Environment(\.colors) private var colors

    private var open: Bool {
        opened.contains(path) || (depth < openDepth && !opened.contains("!" + path))
    }

    var body: some View {
        if item.isLeaf {
            LeafRow(label: label, value: item, path: path, limit: limit, expanded: $expanded)
        } else if item.isScalarArray {
            // A set of values is one fact, not a branch to walk into.
            LeafRow(
                label: label, text: DataFormat.scalarArray(item.arrayItems),
                path: path, limit: limit, expanded: $expanded
            )
        } else {
            branch
        }
    }

    private var branch: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(Animations.smooth) { toggle() }
            } label: {
                branchRow
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                open ? Localized.DataCard.collapseHint(label)
                    : Localized.DataCard.expandHint(label)
            )

            if open {
                foldBody
                    .padding(.leading, Spacing.n24)
                    .background(alignment: .leading) {
                        // The rule the rows hang off, starting under the caret
                        // that opened them.
                        Rectangle()
                            .fill(colors.border.standard.base)
                            .frame(width: 1)
                            .offset(x: 5.5)
                    }
                    .padding(.top, rowPitch)
            }
        }
    }

    private var branchRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.n4) {
            caret
            Text(DataFormat.label(label))
                .textStyle(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            Text(summary)
                .textStyle(Typography.descriptionSmall)
                .foregroundStyle(colors.text.standard.muted)
                .opacity(open ? 0 : 1)
                .frame(
                    maxWidth: .infinity,
                    alignment: align == .justified ? .trailing : .leading
                )
        }
    }

    /// The chat feed's rotating chevron, at the scale a fact row reads at: it
    /// points at what it will open and down at what it has.
    private var caret: some View {
        Iconography.Functional.Chevron.right
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 12, height: 12)
            // The guide value is how far below the view's top the baseline
            // sits. Counted from there, the chevron centers on the label's
            // cap box: half the glyph below the cap's own midpoint.
            .alignmentGuide(.firstTextBaseline) { _ in
                12 / 2 + Typography.miniLabel.uiFont.capHeight / 2
            }
            .foregroundStyle(colors.icon.standard.muted)
            .rotationEffect(.degrees(open ? 90 : 0))
    }

    /// What is inside, in the unit the thing is measured in: a list has items,
    /// an object has values. Shown only while closed — once it is open, the
    /// content is the answer and the count is in the way.
    private var summary: String {
        if case .array = item {
            return Localized.DataCard.itemsCount(String(item.count))
        }
        return Localized.DataCard.valuesCount(String(item.count))
    }

    @ViewBuilder private var foldBody: some View {
        if let columns = item.uniformColumns() {
            DataTableView(
                items: item.arrayItems, columns: columns,
                path: path, preview: preview, expanded: $expanded
            )
        } else {
            DataLevelRows(
                value: item, align: align, openDepth: openDepth,
                preview: preview, limit: limit,
                path: path, depth: depth + 1,
                opened: $opened, expanded: $expanded
            )
        }
    }

    private func toggle() {
        // A default-open branch needs a closed marker; nothing else can say it.
        if open {
            opened.remove(path)
            opened.insert("!" + path)
        } else {
            opened.remove("!" + path)
            opened.insert(path)
        }
    }
}

// MARK: - Leaf row

/// One fact: a label, and its value. Long values cut at a word boundary and
/// offer the rest; prose takes its own line, full width.
private struct LeafRow: View {
    let label: String
    var value: DataValue?
    var text: String?
    let path: String
    let limit: Int
    @Binding var expanded: Set<String>

    @Environment(\.colors) private var colors
    @Environment(\.dataRowLayout) private var layout

    private var content: String {
        if let text { return text }
        return DataFormat.value(value ?? .null)
    }

    private var isProse: Bool {
        DataFormat.isProse(content)
    }

    private var cut: Bool {
        content.count > limit && !expanded.contains(path)
    }

    var body: some View {
        Group {
            if isProse {
                stacked
            } else {
                beside
            }
        }
        .animation(Animations.smooth, value: cut)
    }

    private var beside: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            gutter
            Text(DataFormat.label(label))
                .textStyle(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
            valueText
                .textStyle(Typography.descriptionSmall)
                .foregroundStyle(colors.text.standard.base)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, Spacing.n12)
                .frame(
                    maxWidth: .infinity,
                    alignment: layout.align == .justified ? .trailing : .leading
                )
        }
    }

    /// Prose breaks the two-column rule. Past a few words a value beside its
    /// label stops reading as a pair — the label ends up alongside a
    /// paragraph, and the column is too narrow to read — so the label takes
    /// its own line and the text runs the full width.
    private var stacked: some View {
        HStack(alignment: .top, spacing: 0) {
            gutter
            VStack(alignment: .leading, spacing: stackedGap) {
                Text(DataFormat.label(label))
                    .textStyle(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                valueText
                    .textStyle(Typography.descriptionSmall)
                    .foregroundStyle(colors.text.standard.base)
                    .fixedSize(horizontal: false, vertical: true)
                if cut {
                    showMore
                        // Web's 4pt margin is measured between trimmed boxes.
                        .padding(.top, Spacing.n4)
                }
            }
        }
    }

    /// The room a caret costs. Web drops the caret column and its gap
    /// together on a flat level, so a flat row starts at the card's edge.
    private var gutter: some View {
        Group {
            if layout.flat {
                EmptyView()
            } else {
                Color.clear.frame(width: 12, height: 1)
                    .padding(.trailing, Spacing.n4)
            }
        }
    }

    private var valueText: Text {
        // A cut ends mid-sentence with no trailing air, while the full value
        // often ends in newlines; kept, they read as a blank line and double
        // the air below an expanded value. Trailing whitespace carries no
        // fact, so it is dropped once the whole value is on screen.
        if cut {
            return Text(DataFormat.head(content, limit: limit) + "…")
        }
        return Text(content.replacingOccurrences(
            of: "[ \\n\\t]+$",
            with: "",
            options: .regularExpression
        ))
    }

    private var showMore: some View {
        ShowMoreButton {
            expanded.insert(path)
        }
    }
}

// MARK: - Table

/// A list of matching records, read as a grid: every item shares a shape, so
/// the columns are honest.
private struct DataTableView: View {
    let items: [DataValue]
    let columns: [String]
    let path: String
    let preview: Int
    @Binding var expanded: Set<String>

    @Environment(\.colors) private var colors

    var body: some View {
        VStack(alignment: .leading, spacing: rowPitch) {
            ScrollView(.horizontal, showsIndicators: false) {
                // SwiftUI.Grid — the design system's Grid token shadows it.
                SwiftUI.Grid(
                    alignment: .leading,
                    horizontalSpacing: Spacing.n16,
                    verticalSpacing: rowPitch
                ) {
                    GridRow(alignment: .firstTextBaseline) {
                        ForEach(columns, id: \.self) { column in
                            Text(DataFormat.label(column))
                                .textStyle(Typography.miniLabel)
                                .foregroundStyle(colors.text.standard.muted)
                                .padding(.bottom, Spacing.n4)
                        }
                    }
                    ForEach(Array(items.enumerated().prefix(preview)), id: \.offset) { _, row in
                        cells(row)
                    }
                    if expanded.contains(path), items.count > preview {
                        ForEach(
                            Array(items.enumerated().dropFirst(preview)),
                            id: \.offset
                        ) { _, row in
                            cells(row)
                                .transition(DataArrive.transition)
                        }
                    }
                }
                // Trimmed cells end at the baseline; keep descenders inside the scroll viewport.
                .padding(.bottom, max(0, -Typography.descriptionSmall.uiFont.descender))
            }
            if items.count > preview, !expanded.contains(path) {
                ShowAllButton(count: items.count) {
                    expanded.insert(path)
                }
            }
        }
    }

    private func cells(_ row: DataValue) -> some View {
        SwiftUI.GridRow(alignment: .firstTextBaseline) {
            ForEach(columns, id: \.self) { column in
                Text(DataFormat.value(row.value(forKey: column) ?? .null))
                    .textStyle(Typography.descriptionSmall)
                    .foregroundStyle(colors.text.standard.base)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

// MARK: - Actions

/// A long list shows its head and offers the rest, rather than running past
/// the end of the sheet. It is the one thing in the card asking to be pressed,
/// so it is the one thing carrying the accent.
private struct ShowAllButton: View {
    let count: Int
    let action: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        Button {
            withAnimation(Animations.smooth) { action() }
        } label: {
            Text(Localized.DataCard.showAll(String(count)))
                .textStyle(Typography.tag)
                .foregroundStyle(colors.accent)
        }
        .buttonStyle(.plain)
    }
}

private struct ShowMoreButton: View {
    let action: () -> Void

    @Environment(\.colors) private var colors

    var body: some View {
        Button {
            withAnimation(Animations.smooth) { action() }
        } label: {
            Text(Localized.DataCard.showMore)
                .textStyle(Typography.tag)
                .foregroundStyle(colors.accent)
        }
        .buttonStyle(.plain)
    }
}

/// A value that just grew past its limit arrives rather than snapping.
enum DataArrive {
    static var transition: AnyTransition {
        .opacity.combined(with: .offset(y: -Spacing.n4))
    }
}

// MARK: - Row environment

/// How a row lays out its columns — set by the level that owns it. A level
/// with nothing to open keeps no room for a caret: its rows start at the
/// level's own edge, and the card's root follows the same rule as any level
/// below it.
private struct DataRowLayout {
    let flat: Bool
    let align: DataRows.Align
}

private extension EnvironmentValues {
    @Entry var dataRowLayout: DataRowLayout = .init(flat: true, align: .justified)
}
