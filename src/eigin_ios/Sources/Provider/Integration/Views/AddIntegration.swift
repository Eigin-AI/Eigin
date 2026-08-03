import Factory
import SwiftData
import SwiftUI

/// Sheet for connecting a new integration: pick a type, run its auth flow, save.
///
/// The category grid and the search field act as filters over the bundled
/// types. An active category shows as a removable chip; clearing it returns to
/// the grid.
struct AddIntegration: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colors) private var colors
    @Injected(\.integrationOAuthService) private var oauthService
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]

    @State private var phase: Phase = .picking
    /// Active category filter. `nil` shows the browse grid.
    @State private var selectedCategory: IntegrationCategory?
    @State private var searchText: String
    @State private var partialGrantWarning: String?
    @State private var showingAddIMAPAccount = false
    /// Set (with Aula's OAuth config) to present the WKWebView login sheet.
    @State private var pendingAulaConfig: PKCEOAuthConfig?

    /// The parameters exist so previews can open straight onto a given filter
    /// state; the app always uses the defaults and filters by tapping/typing.
    init(category: IntegrationCategory? = nil, searchText: String = "") {
        _selectedCategory = State(initialValue: category)
        _searchText = State(initialValue: searchText)
    }

    private let columns = [
        GridItem(.flexible(), spacing: Sizing.PageLayout.ContentGrouping.gap),
        GridItem(.flexible(), spacing: Sizing.PageLayout.ContentGrouping.gap),
    ]

    var body: some View {
        VStack(spacing: 0) {
            AppSheetHeader(
                title: Localized.Settings.Action.addIntegration,
                description: Localized.Integrations.AddSheet.description,
                onDismiss: { dismiss() }
            )
            .padding(.top, Spacing.n24)
            .padding(.bottom, Spacing.n8)

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    switch phase {
                    case .picking:
                        browseOrCategoryContent
                    case .authorizing:
                        statusCard {
                            HStack(spacing: Spacing.n8) {
                                ProgressView()
                                Text(Localized.Auth.waiting)
                                    .typography(Typography.tag)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                    case .error(let message):
                        statusCard {
                            VStack(alignment: .leading, spacing: Spacing.n8) {
                                Label(
                                    Localized.Errors.Connection.title,
                                    systemImage: "exclamationmark.triangle"
                                )
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.error)
                                Text(message)
                                    .typography(Typography.tag)
                                    .foregroundStyle(colors.text.standard.muted)
                            }
                        }
                        browseOrCategoryContent
                    }
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(Radius.card)
        .alert(
            Localized.Ui.integrations,
            isPresented: Binding(
                get: { partialGrantWarning != nil },
                set: { if !$0 { partialGrantWarning = nil } }
            )
        ) {
            Button("OK") { dismiss() }
        } message: {
            Text(partialGrantWarning ?? "")
        }
        .sheet(isPresented: $showingAddIMAPAccount) {
            AddIMAPAccount(onConnected: { dismiss() })
        }
        .sheet(
            isPresented: Binding(
                get: { pendingAulaConfig != nil },
                set: { if !$0 { pendingAulaConfig = nil } }
            )
        ) {
            if let config = pendingAulaConfig {
                AddAulaAccount(onConnected: { dismiss() }, config: config)
            }
        }
    }

    // MARK: - Browse

    /// The types on offer once the category and search filters are applied.
    /// `nil` when neither filter is active, which is when the grid shows.
    private var filteredTypes: [IntegrationType]? {
        let scope = selectedCategory?.integrationTypes ?? BundledIntegrationType.all
        if !searchText.isEmpty {
            return IntegrationSearch.matching(searchText, in: scope)
        }
        return selectedCategory == nil ? nil : scope
    }

    private var browseOrCategoryContent: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            searchField

            // Group the chip with the list it filters.
            VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                if let category = selectedCategory {
                    categoryChip(category)
                }

                if let types = filteredTypes {
                    resultsList(types)
                } else {
                    categoryGrid
                }
            }
        }
    }

    /// The active category filter. Tapping it clears the filter and returns to
    /// the grid.
    private func categoryChip(_ category: IntegrationCategory) -> some View {
        AppTag(
            category.displayName,
            action: { withAnimation(Animations.snap) { selectedCategory = nil } }
        ) {
            Image(systemName: "xmark")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHint(Localized.Integrations.Filter.clear)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.n8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(colors.text.standard.muted)
            TextField(Localized.Integrations.Search.placeholder, text: $searchText)
                .typography(Typography.description)
                .foregroundStyle(colors.text.standard.base)
        }
        .padding(.horizontal, Sizing.Input.Px.left)
        .frame(height: Sizing.Input.height)
        .background(colors.input.standard.active)
        .clipShape(Capsule())
    }

    private var categoryGrid: some View {
        LazyVGrid(columns: columns, spacing: Sizing.PageLayout.ContentGrouping.gap) {
            ForEach(IntegrationCategory.browseOrder) { category in
                categoryTile(category)
            }
        }
    }

    private func categoryTile(_ category: IntegrationCategory) -> some View {
        let tile = VStack(spacing: Spacing.n16) {
            Image(systemName: category.systemImage)
                .font(.system(size: 28))
                .foregroundStyle(colors.text.standard.base)
            Text(category.displayName)
                .typography(Typography.button)
                .foregroundStyle(colors.text.standard.base)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.n24)
        .padding(.horizontal, Spacing.n8)
        .background(
            colors.button.standard.secondary,
            in: RoundedRectangle(cornerRadius: Radius.card)
        )

        return Group {
            if category.isAvailable {
                Button {
                    withAnimation(Animations.snap) { selectedCategory = category }
                } label: {
                    tile
                }
                .buttonStyle(.plain)
            } else {
                // Categories awaiting their first provider stay visible for
                // discoverability, dimmed and inert.
                tile.opacity(0.5)
            }
        }
    }

    @ViewBuilder
    private func resultsList(_ types: [IntegrationType]) -> some View {
        if types.isEmpty {
            Text(Localized.Integrations.Search.noResults)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n8)
        } else {
            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(types.enumerated()), id: \.element.id) { index, type in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.n24)
                        }
                        integrationRow(type, subtitle: subtitle(for: type))
                    }
                }
            }
        }
    }

    /// Prefix the category only when the list spans categories — once a category
    /// chip is active, repeating it on every row is noise.
    private func subtitle(for type: IntegrationType) -> String {
        selectedCategory == nil
            ? "\(type.category.displayName) · \(type.description)"
            : type.description
    }

    /// A row for one integration type, tapped to run `connect(_:)`. A type with
    /// an existing connection is inert and marked with a checkmark, since this
    /// sheet connects one account per type.
    private func integrationRow(_ type: IntegrationType, subtitle: String) -> some View {
        Group {
            if isConnected(type) {
                HStack(spacing: Spacing.n16) {
                    integrationRowLabel(type, subtitle: subtitle)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.icon.signal.approve)
                }
                .padding(.horizontal, Spacing.n24)
                .padding(.vertical, Spacing.n16)
            } else {
                Button { connect(type) } label: {
                    HStack(spacing: Spacing.n16) {
                        integrationRowLabel(type, subtitle: subtitle)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                    .padding(.horizontal, Spacing.n24)
                    .padding(.vertical, Spacing.n16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func integrationRowLabel(_ type: IntegrationType, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.n4) {
            Text(type.displayName)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Text(subtitle)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
        }
    }

    private func isConnected(_ type: IntegrationType) -> Bool {
        integrations.contains { $0.isEnabled && $0.typeID == type.id }
    }

    private func statusCard(@ViewBuilder content: @escaping () -> some View) -> some View {
        AppCardSurface { content() }
    }

    // MARK: - Connect

    private func connect(_ type: IntegrationType) {
        // More than one provider can grant the same capability (e.g. Google
        // and Microsoft both provide `.email`) — `IntegrationManager` already
        // defends against two connected integrations both contributing
        // same-named tools for it, keeping only the first-connected one, so no
        // guard is needed here beyond that.
        switch type.authKind {
        case .oauth(let configFactory):
            connectOAuth(type, configFactory: configFactory)
        case .imap:
            showingAddIMAPAccount = true
        case .webSession(let configFactory):
            connectWebSession(type, configFactory: configFactory)
        }
    }

    private func connectWebSession(
        _ type: IntegrationType,
        configFactory: @Sendable () -> PKCEOAuthConfig
    ) {
        let config = configFactory()
        // Same fail-fast as OAuth: without the client id, the login page can't
        // complete, which would read to the user as a silent hang.
        guard !config.clientID.isEmpty else {
            phase = .error(
                "\(type.displayName) isn't configured in this build — its OAuth client id is missing."
            )
            return
        }
        pendingAulaConfig = config
    }

    private func connectOAuth(
        _ type: IntegrationType,
        configFactory: @Sendable () -> PKCEOAuthConfig
    ) {
        let config = configFactory()
        // Client id comes from a build-time secret (see `.env` / project.yml) —
        // if it's missing, authorize() would still launch a browser session
        // that can never complete (Google rejects an empty client_id), which
        // reads to the user as a silent hang. Fail fast with a clear reason.
        guard !config.clientID.isEmpty else {
            phase = .error(
                "\(type.displayName) isn't configured in this build — its OAuth client id is missing."
            )
            return
        }
        phase = .authorizing

        Task {
            let integrationID = UUID()
            do {
                let accessToken = try await oauthService.authorize(
                    config: config,
                    integrationID: integrationID
                )
                let accountLabel = await type.accountLabel(accessToken) ?? type.displayName

                // Google's consent screen lets the user deny individual scopes, so
                // don't assume every requested capability was granted.
                let grantedScopes = oauthService.grantedScopes(for: integrationID)
                let grantedCapabilities = type.grantedCapabilities(fromGrantedScopes: grantedScopes)

                // Reuse the id authorize() already stored tokens under — no need to
                // migrate keychain keys to a separately-minted model id.
                let integration = Integration(
                    id: integrationID,
                    typeID: type.id,
                    accountLabel: accountLabel,
                    grantedCapabilities: grantedCapabilities.map(\.rawValue)
                )
                modelContext.insert(integration)

                let ungranted = type.providedCapabilities.subtracting(grantedCapabilities)
                if !ungranted.isEmpty {
                    let names = ungranted.map(\.rawValue.titleCased).joined(separator: ", ")
                    partialGrantWarning =
                        "\(accountLabel) is connected, but you didn't grant: \(names). The agent won't be able to use those until you reconnect and approve them."
                } else {
                    Haptics.success()
                    dismiss()
                }
            } catch IntegrationOAuthError.userCancelled {
                phase = .picking
            } catch {
                phase = .error(error.localizedDescription)
                Haptics.error()
            }
        }
    }

    private enum Phase: Equatable {
        case picking
        case authorizing
        case error(String)
    }
}

#Preview("Browse") {
    AddIntegration()
        .previewEnvironment()
}

#Preview("Browse — some already connected") {
    AddIntegration()
        .previewEnvironment(seed: PreviewIntegrations.seedConnected)
}

#Preview("Filtered — Email") {
    AddIntegration(category: .email)
        .previewEnvironment()
}

#Preview("Filtered — Email, one connected") {
    AddIntegration(category: .email)
        .previewEnvironment(seed: PreviewIntegrations.seedConnected)
}

#Preview("Search — across categories") {
    AddIntegration(searchText: "mail")
        .previewEnvironment(seed: PreviewIntegrations.seedConnected)
}

#Preview("Search — within a category filter") {
    AddIntegration(category: .email, searchText: "google")
        .previewEnvironment()
}

#Preview("Search — no results") {
    AddIntegration(searchText: "spotify")
        .previewEnvironment()
}
