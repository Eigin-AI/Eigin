import SwiftUI

/// Everything one connection offers, read-only: a server's tools, an agent's
/// skills, an account's capabilities.
///
/// Unlike a provider's models there is no choice to make — Eigin picks what a
/// chat needs, and setting that by hand would be a setting nobody has the
/// information to set. So this is a list to check rather than to change,
/// which is why it needs no groups and no controls: the only interaction is
/// finding something in it.
struct OffersScreen: View {
    let items: [String]
    let noun: String

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""

    private var shown: [String] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return items }
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        return items.filter { $0.lowercased().contains(query) }
    }

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                AppSearchField(
                    text: $searchText,
                    placeholder: Localized.Integration.Offers.searchPlaceholder(
                        "\(items.count)",
                        noun
                    )
                )

                if shown.isEmpty {
                    AppEmptyState(
                        icon: Iconography.Functional.search,
                        title: searchText.isEmpty ? Localized.Integration.Offers
                            .emptyTitle : Localized.Integration.Offers.noMatchesTitle,
                        description: searchText.isEmpty ? Localized.Integration.Offers
                            .emptyHint : Localized.Integration.Offers.noMatches(searchText)
                    ) {
                        if !searchText.isEmpty {
                            AppButton(Localized.Model.Picker.clearSearch, variant: .secondary) {
                                searchText = ""
                            }
                        }
                    }
                } else {
                    AppRowsGroup(
                        footnote: Localized.Integration.Offers.footnote,
                        rows: shown.map { item in
                            AppRowSpec(id: item, title: item, accessory: .none)
                        }
                    )
                }
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        } header: {
            AppNavigationHeader(
                title: Localized.Integration.Offers.title,
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
    }
}

#Preview {
    OffersScreen(
        items: ["Create issue", "Update issue", "Search issues", "List projects"],
        noun: "tools"
    )
    .previewEnvironment()
}
