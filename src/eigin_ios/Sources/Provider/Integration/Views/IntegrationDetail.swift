import Factory
import SwiftData
import SwiftUI

/// Detail view for a connected integration: account, granted capabilities,
/// in-place reconnect, disconnect.
struct IntegrationDetail: View {
    let integration: Integration
    @Injected(\.integrationManager) private var integrationManager
    @Injected(\.integrationOAuthService) private var oauthService
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showRemoveConfirmation = false
    @State private var isReconnecting = false
    @State private var reconnectError: String?
    /// Set (with Aula's OAuth config) to present the reconnect login sheet.
    @State private var showingAulaReconnect = false
    @State private var showingIMAPReconnect = false
    @State private var partialGrantWarning: String?

    private var type: IntegrationType? {
        BundledIntegrationType.type(forID: integration.typeID)
    }

    private var needsReconnect: Bool {
        IntegrationHealthMonitor.shared.needsReconnect(integration, oauthService: oauthService)
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: integration.accountLabel,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            ScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    if needsReconnect {
                        attentionCard
                    }
                    infoCard
                    if hasPartialGrant {
                        capabilitiesCard
                    }
                    reconnectCard
                    removeCard
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(integration.accountLabel, isPresented: $showRemoveConfirmation) {
            Button(Localized.Integrations.Action.disconnect, role: .destructive) { remove() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        }
        .alert(
            Localized.Ui.integrations,
            isPresented: Binding(
                get: { partialGrantWarning != nil },
                set: { if !$0 { partialGrantWarning = nil } }
            )
        ) {
            Button("OK") {}
        } message: {
            Text(partialGrantWarning ?? "")
        }
        .sheet(isPresented: $showingAulaReconnect) {
            AddAulaAccount(
                onConnected: { Haptics.success() },
                config: AulaOAuth.config(),
                existing: integration
            )
        }
        .sheet(isPresented: $showingIMAPReconnect) {
            AddIMAPAccount(
                onConnected: { Haptics.success() },
                existing: integration
            )
        }
    }

    private var infoCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                infoRow(
                    label: Localized.Common.Fields.name,
                    value: type?.displayName ?? integration.typeID
                )
                Divider().padding(.leading, Spacing.n24)
                infoRow(label: Localized.Common.Fields.account, value: integration.accountLabel)
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(label)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Spacer()
            Text(value)
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
    }

    /// All capabilities the type can provide, each flagged with whether this
    /// specific connection actually granted it — Google's consent screen lets
    /// scopes be denied individually, so "connected" doesn't imply "fully granted".
    private var allCapabilities: [(capability: Capability, granted: Bool)] {
        let granted = Set(integration.grantedCapabilities)
        let all = type?
            .providedCapabilities ??
            Set(integration.grantedCapabilities.compactMap(Capability.init))
        return all.sorted { $0.rawValue < $1.rawValue }.map { ($0, granted.contains($0.rawValue)) }
    }

    /// Whether the account is missing any capability its type provides, which
    /// happens when consent is given for only some of the requested scopes.
    private var hasPartialGrant: Bool {
        allCapabilities.contains { !$0.granted }
    }

    private var capabilitiesCard: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Ui.integrations)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(
                        Array(allCapabilities.enumerated()),
                        id: \.element.capability
                    ) { index, entry in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.n24)
                        }
                        HStack {
                            Text(entry.capability.rawValue.titleCased)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.text.standard.base)
                            Spacer()
                            Image(systemName: entry
                                .granted ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(entry.granted ? .green : colors.text.standard
                                    .muted)
                        }
                        .padding(.horizontal, Spacing.n24)
                        .padding(.vertical, Spacing.n16)
                    }
                }
            }

            if allCapabilities.contains(where: { !$0.granted }) {
                Text(
                    "Not granted — reconnect this integration to approve the permissions you skipped."
                )
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Spacing.n8)
            }

            // Tool-level permissions for this capability are managed in the
            // main permissions screen, grouped like any other external tool —
            // connecting an integration doesn't hide them from user control.
        }
    }

    private var attentionCard: some View {
        AppCardSurface {
            VStack(alignment: .leading, spacing: Spacing.n8) {
                Label(
                    Localized.Integrations.Attention.title,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.error)
                Text(Localized.Integrations.Attention.body)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
        }
    }

    private var reconnectCard: some View {
        VStack(spacing: Spacing.n8) {
            if let reconnectError {
                AppCardSurface {
                    VStack(alignment: .leading, spacing: Spacing.n8) {
                        Label(
                            Localized.Errors.Connection.title,
                            systemImage: "exclamationmark.triangle"
                        )
                        .typography(Typography.titleXS)
                        .foregroundStyle(colors.text.standard.error)
                        Text(reconnectError)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }
            }

            if isReconnecting {
                AppButton(
                    Localized.Integrations.Action.reconnect,
                    variant: .secondary
                ) {}
                    .disabled(true)
                    .overlay { ProgressView() }
            } else {
                AppButton(
                    Localized.Integrations.Action.reconnect,
                    variant: .secondary
                ) {
                    reconnect()
                }
            }
        }
    }

    private func reconnect() {
        guard let type else { return }
        switch type.authKind {
        case .oauth(let configFactory):
            reconnectOAuth(type, configFactory: configFactory)
        case .imap:
            showingIMAPReconnect = true
        case .webSession(let configFactory):
            // Same fail-fast as the add flow: without the client id, the
            // login page can't complete, which would read as a silent hang.
            let config = configFactory()
            guard !config.clientID.isEmpty else {
                reconnectError = IntegrationOAuthError.notConfigured(
                    type.displayName
                ).localizedDescription
                return
            }
            showingAulaReconnect = true
        }
    }

    /// Re-runs the OAuth flow under the *existing* integration id, so the
    /// keychain namespace and every selection referencing it survive — model
    /// in place, only the connection's credentials and grants refresh.
    private func reconnectOAuth(
        _ type: IntegrationType,
        configFactory: @escaping @Sendable () -> PKCEOAuthConfig
    ) {
        isReconnecting = true
        reconnectError = nil

        Task {
            do {
                let result = try await IntegrationConnect.authorizeOAuth(
                    oauthService: oauthService,
                    type: type,
                    config: configFactory(),
                    integrationID: integration.id,
                    labelFallback: integration.accountLabel
                )

                integration.accountLabel = result.accountLabel
                integration.grantedCapabilities = result.grantedCapabilities.map(\.rawValue)
                integration.updatedAt = .now
                IntegrationHealthMonitor.shared.clearNeedsReconnect(integration.id)
                isReconnecting = false

                let ungranted = type.providedCapabilities.subtracting(result.grantedCapabilities)
                if !ungranted.isEmpty {
                    let names = ungranted.map(\.rawValue.titleCased).joined(separator: ", ")
                    partialGrantWarning =
                        "\(result.accountLabel) is connected, but you didn't grant: \(names). The agent won't be able to use those until you reconnect and approve them."
                } else {
                    Haptics.success()
                }
            } catch IntegrationOAuthError.userCancelled {
                isReconnecting = false
            } catch {
                reconnectError = error.localizedDescription
                isReconnecting = false
                Haptics.error()
            }
        }
    }

    private var removeCard: some View {
        AppButton(Localized.Integrations.Action.disconnect, variant: .destructive) {
            showRemoveConfirmation = true
        }
    }

    private func remove() {
        integrationManager.disconnect(integration)
        // Fall back to the next connected provider for any capability this
        // integration was the explicit active choice for.
        integrationManager.clearSelections(referencing: integration.id, in: modelContext)
        modelContext.delete(integration)
        dismiss()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

#Preview("Fully granted") {
    let integration = Integration(
        typeID: "google",
        accountLabel: "daniel@gmail.com",
        grantedCapabilities: [Capability.email.rawValue]
    )
    return NavigationStack {
        IntegrationDetail(integration: integration)
    }
    .previewEnvironment { $0.insert(integration) }
}

#Preview("Partial grant") {
    // Google provides `.email` but nothing was granted, so the
    // granted-capabilities card appears.
    let integration = Integration(
        typeID: "google",
        accountLabel: "daniel@gmail.com",
        grantedCapabilities: []
    )
    return NavigationStack {
        IntegrationDetail(integration: integration)
    }
    .previewEnvironment { $0.insert(integration) }
}

#Preview("Aula") {
    let integration = Integration(
        typeID: "aula",
        accountLabel: "Ada",
        grantedCapabilities: [Capability.aula.rawValue]
    )
    return NavigationStack {
        IntegrationDetail(integration: integration)
    }
    .previewEnvironment { $0.insert(integration) }
}
