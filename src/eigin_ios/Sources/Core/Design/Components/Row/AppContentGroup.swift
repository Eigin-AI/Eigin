import SwiftUI

/// Rows gather into a card. The section label sits above the card and the
/// footnote below it — small print belongs to the group rather than the page,
/// so it is a prop here. Hairlines separate rows, inset to the row text.
struct AppContentGroup<Content: View>: View {
    var label: String?
    var footnote: String?
    @ViewBuilder private var content: () -> Content

    @Environment(\.colors) private var colors

    init(
        label: String? = nil,
        footnote: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.label = label
        self.footnote = footnote
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.n8) {
            if let label {
                Text(label)
                    .typography(Typography.miniLabel)
                    .foregroundStyle(colors.text.standard.muted)
                    .padding(.horizontal, Spacing.n24)
            }

            AppCardSurface(padding: 0) { VStack(spacing: 0) { content() } }

            if let footnote {
                Text(footnote)
                    .typography(Typography.note)
                    .foregroundStyle(colors.text.standard.muted)
                    .padding(.horizontal, Spacing.n24)
            }
        }
    }
}

/// A content group whose rows are plain `AppRowSpec`s: the common case, and
/// the one that gets automatic hairlines between rows.
struct AppRowsGroup: View {
    var label: String?
    var footnote: String?
    var rows: [AppRowSpec]

    var body: some View {
        AppContentGroup(label: label, footnote: footnote) {
            ForEachWithIndex(data: rows) { index, row in
                if index > 0 { RowHairline() }
                AppRow(row)
                    .id(row.id)
            }
        }
    }
}

/// The hairline between rows inside a row card: 1pt, inset to the text.
struct RowHairline: View {
    @Environment(\.colors) private var colors

    var body: some View {
        Rectangle()
            .fill(colors.input.standard.inactive)
            .frame(height: 1)
            .padding(.leading, Spacing.n24)
    }
}

/// ForEach with the index, so leading hairlines can skip the first row.
private struct ForEachWithIndex<Data: RandomAccessCollection, Content: View>: View
    where Data.Element: Identifiable
{
    let data: Data
    @ViewBuilder let content: (Int, Data.Element) -> Content

    var body: some View {
        ForEach(Array(data.enumerated()), id: \.element.id) { index, element in
            content(index, element)
        }
    }
}

// MARK: - Preview

private struct AppRowsGroupPreview: View {
    var body: some View {
        VStack(spacing: Spacing.n32) {
            AppRowsGroup(
                label: "AI providers",
                rows: [
                    AppRowSpec(title: "Eigin Relay", description: "Private cloud AI"),
                    AppRowSpec(title: "Anthropic", description: "7 models"),
                    AppRowSpec(
                        title: "Google",
                        description: "Mail, calendar and contacts",
                        trailing: .status(.attention, "Reconnect")
                    ),
                    AppRowSpec(title: "Add provider", accessory: .plus, tone: .accent),
                ]
            )
            AppRowsGroup(
                footnote: "3 of 47 appear in your agent tab.",
                rows: [
                    AppRowSpec(
                        title: "Claude Opus 4.6",
                        trailing: .toggle(isOn: true, isDisabled: false, action: {})
                    ),
                    AppRowSpec(
                        title: "Claude Sonnet 4.6",
                        trailing: .toggle(isOn: false, isDisabled: false, action: {})
                    ),
                ]
            )
        }
        .padding(Spacing.n24)
        .background(colors.surface.standard.base)
    }

    @Environment(\.colors) private var colors
}

#Preview("Light") {
    AppRowsGroupPreview()
        .resolveTheme()
}

#Preview("Dark") {
    AppRowsGroupPreview()
        .resolveTheme()
        .environment(\.colorScheme, .dark)
}
