import Factory
import SwiftData
import SwiftUI

/// Catalogue content for adding anything Eigin can reach.
///
/// People arrive knowing what they want it to do, not which protocol it
/// speaks, so the catalogue is sorted by that and the mechanism never appears
/// here — an MCP server and a built-in account are entries on the same list.
/// Browsing narrows the sheet in place rather than pushing a screen: the chip
/// names the list, search stays available, and connect-by-address stays where
/// it is. The presenting view draws the header and stacks the connect sheet
/// on top, the same way the provider flow does. Replaces the old integration
/// and MCP add sheets.
struct AddIntegrationSheetContent: View {
    @Injected(\.integrationOAuthService) private var oauthService
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]

    /// An entry was picked; the presenter stacks the connect sheet.
    let onSelect: (ConnectTarget) -> Void

    @State private var searchText = ""
    /// Active category filter. `nil` shows Recommended plus Browse.
    @State private var selectedCategory: IntegrationCategory?

    var body: some View {
        Group {
            VStack(spacing: Sizing.PageLayout.gap) {
                contents
            }
            .padding(.horizontal, Spacing.n16)
            .padding(.top, Spacing.n8)
            .padding(.bottom, Spacing.n32)
        }
    }

    @Environment(\.colors) private var colors

    // MARK: - Contents

    @ViewBuilder
    private var contents: some View {
        AppSearchField(
            text: $searchText,
            placeholder: Localized.Integration.Add.searchPlaceholder
        )

        // The chip states where you are; the list below drops its own label,
        // because the chip names it.
        if let selectedCategory {
            AppTag(selectedCategory.displayName, action: {
                withAnimation(.easeOut(duration: Animations.fast)) { self.selectedCategory = nil }
            }) {
                Iconography.Functional.x
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }

        if queryHasNoMatches {
            AppNotice(
                tone: .info,
                title: noMatchesTitle,
                body: noMatchesBody
            )
            .transition(.opacity)
        }

        if !listedTypes.isEmpty {
            AppRowsGroup(label: listLabel, rows: listedTypes.map(typeRowSpec))
                .transition(.opacity)
        }

        if let categories = shownCategories {
            AppRowsGroup(
                label: Localized.Integration.Add.browseLabel,
                rows: categories.map { category in
                    AppRowSpec(
                        id: category.rawValue,
                        title: category.displayName,
                        icon: categoryIcon(category),
                        action: {
                            withAnimation(.easeOut(duration: Animations.fast)) {
                                selectedCategory = category
                            }
                        }
                    )
                }
            )
            .transition(.opacity)
        }

        // The way in for anything we have never heard of never moves — and it
        // promises only a try, since what answers there decides what we can
        // do with it.
        AppRowsGroup(
            footnote: Localized.Integration.Add.addressFootnote,
            rows: [
                AppRowSpec(
                    id: "address",
                    title: Localized.Integration.Add.connectByAddress,
                    icon: Iconography.Functional.globe,
                    action: { onSelect(.address) }
                ),
            ]
        )
    }

    // MARK: - Catalogue

    /// The catalogue narrowed by search or category. At the top level that
    /// is the Recommended list — the things we would suggest first — minus
    /// anything already connected, because the sheet connects one account
    /// per type and offering it again would be offering a thing you cannot do.
    private var listedTypes: [IntegrationType] {
        let types = if let selectedCategory {
            searchText.isEmpty
                ? selectedCategory.integrationTypes
                : IntegrationSearch.matching(searchText, in: selectedCategory.integrationTypes)
        } else {
            searchText.isEmpty
                ? BundledIntegrationType.recommended
                : IntegrationSearch.matching(searchText, in: BundledIntegrationType.all)
        }
        return types.filter { !isConnected($0) }
    }

    /// Only categories with something in them: an empty one is a promise
    /// Browse can't keep yet.
    private var shownCategories: [IntegrationCategory]? {
        guard searchText.isEmpty, selectedCategory == nil else { return nil }
        return IntegrationCategory.allCases.filter(\.isAvailable)
    }

    private var listLabel: String? {
        if selectedCategory != nil { return nil }
        return searchText.isEmpty
            ? Localized.Integration.Add.recommendedLabel
            : Localized.Integration.Add.matchesLabel
    }

    private var queryHasNoMatches: Bool {
        guard !searchText.isEmpty else { return false }
        return listedTypes.isEmpty
    }

    private var noMatchesTitle: String {
        selectedCategory == nil
            ? Localized.Integration.Add.unknownTitle
            : Localized.Integration.Add.emptyCategoryTitle
    }

    private var noMatchesBody: String {
        selectedCategory == nil
            ? Localized.Integration.Add.unknownBody
            : Localized.Integration.Add.emptyCategoryBody
    }

    private func typeRowSpec(_ type: IntegrationType) -> AppRowSpec {
        AppRowSpec(
            id: type.id,
            title: type.displayName,
            description: type.description,
            icon: rowIcon(for: type),
            action: { onSelect(.type(type)) }
        )
    }

    private func rowIcon(for type: IntegrationType) -> Image? {
        type.brandImage
            ?? Iconography.Functional.mail
    }

    private func categoryIcon(_ category: IntegrationCategory) -> Image? {
        switch category {
        case .email, .music: Iconography.Functional.mail
        case .familyAndSchool: Iconography.Functional.school
        case .platform: Iconography.Functional.lock
        }
    }

    private func isConnected(_ type: IntegrationType) -> Bool {
        integrations.contains { $0.isEnabled && $0.typeID == type.id }
    }
}

extension ConnectTarget: Identifiable {
    var id: String {
        switch self {
        case .type(let type): "type-\(type.id)"
        case .address: "address"
        }
    }
}

#Preview("Browse") {
    AddIntegrationSheetContent(onSelect: { _ in })
        .previewEnvironment()
}

#Preview("Some already connected") {
    AddIntegrationSheetContent(onSelect: { _ in })
        .previewEnvironment(seed: PreviewIntegrations.seedConnected)
}
