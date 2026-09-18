import SwiftUI

/// Semi-structured data, read as facts rather than as syntax — a tool's
/// arguments, an error payload, whatever a service handed back, usually
/// arriving as JSON.
///
/// A table is for data that is already a grid. This is for data that is not:
/// labels on the left, values at the opposite edge, and structure shown by
/// what it is rather than by punctuation. Nesting folds, a set of values
/// becomes one row, and a list of matching records becomes a table after all.
/// Nothing is dropped, so this can stand in place of showing the raw document.
///
/// It shares the elevated surface with tables and code blocks, being the same
/// class of thing: a payload quoted inside a screen, not part of the screen's
/// own prose.
struct DataCard<Footer: View>: View {
    /// The document to read out. Any JSON shape.
    let value: DataValue
    /// Section heading above the card.
    var label: String?
    /// Values beside their label, or driven to the opposite edge.
    var align: DataRows.Align = .justified
    /// How many levels stand open before anything is touched.
    var openDepth = 0
    /// How many rows of a long list are shown before it offers the rest.
    var preview = 5
    /// How many characters of a long value are shown before it offers the rest.
    var limit = 280
    /// Whatever belongs under the card, bound to it at the grouping gap: a
    /// line of small print, an action, both. Left to the caller — a data card
    /// does not assume every use has something to say down there.
    @ViewBuilder var footer: () -> Footer

    init(
        value: DataValue,
        label: String? = nil,
        align: DataRows.Align = .justified,
        openDepth: Int = 0,
        preview: Int = 5,
        limit: Int = 280,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.value = value
        self.label = label
        self.align = align
        self.openDepth = openDepth
        self.preview = preview
        self.limit = limit
        self.footer = footer
    }

    @Environment(\.colors) private var colors

    /// Web renders the footnote only when the caller supplies one; an empty
    /// one must not spend the grouping gap below the card.
    private var hasFooter: Bool {
        Footer.self != EmptyView.self
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label {
                Text(label)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .padding(.horizontal, Spacing.n20)
                    // Web labels are cap-trimmed; the line box's lower air
                    // comes out of the grouping gap.
                    .padding(
                        .bottom,
                        Sizing.PageLayout.ContentGrouping.gap - Typography.miniLabel.lineBoxInset
                    )
            }

            DataRows(
                value: value,
                align: align,
                openDepth: openDepth,
                preview: preview,
                limit: limit
            )
            .padding(.top, Spacing.n20 - Typography.miniLabel.lineBoxInset)
            .padding(.bottom, Spacing.n20 - Typography.descriptionSmall.lineBoxInset)
            .padding(.horizontal, Spacing.n20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(colors.surface.standard.elevated)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))

            if hasFooter {
                HStack(spacing: Spacing.n8) {
                    footer()
                }
                .foregroundStyle(colors.text.standard.muted)
                .padding(.top, Sizing.PageLayout.ContentGrouping.gap - Typography.tag.lineBoxInset)
                .padding(.horizontal, Spacing.n20)
            }
        }
    }
}

extension DataCard where Footer == EmptyView {
    /// A card with nothing to say down there.
    init(
        value: DataValue,
        label: String? = nil,
        align: DataRows.Align = .justified,
        openDepth: Int = 0,
        preview: Int = 5,
        limit: Int = 280
    ) {
        self.init(
            value: value, label: label, align: align,
            openDepth: openDepth, preview: preview, limit: limit,
            footer: { EmptyView() }
        )
    }
}

#if DEBUG || EIGIN_DEV
#Preview("Data cards") {
    DataCardGallery()
}

#Preview("Dark") {
    DataCardGallery()
        .environment(\.colorScheme, .dark)
}

private struct DataCardGallery: View {
    @Environment(\.colors) private var colors

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Sizing.PageLayout.gap) {
                ForEach(DataCardExamples.all) { example in
                    DataCard(value: example.value, label: example.label)
                }
            }
            .padding(Spacing.n24)
        }
        .background(colors.surface.standard.base)
        .resolveTheme()
    }
}

#endif
