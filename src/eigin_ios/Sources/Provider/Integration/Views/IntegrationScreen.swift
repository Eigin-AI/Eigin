import Factory
import SwiftData
import SwiftUI

/// One integration, whatever is behind it.
///
/// A built-in account, a server someone runs and another agent are the same
/// thing to the person using them: something Eigin can reach on their behalf.
/// So they share a screen, and the mechanism is a fact row rather than a
/// category — the only place in the app where the word MCP appears at all.
/// Replaces the integration and MCP-server detail screens.
struct IntegrationScreen: View {
    enum Subject: Identifiable {
        case builtin(Integration)
        case server(MCPServer)

        var id: String {
            switch self {
            case .builtin(let integration): "integration-\(integration.id)"
            case .server(let server): "server-\(server.id)"
            }
        }
    }

    let subject: Subject

    @Injected(\.integrationManager) private var integrationManager
    @Injected(\.integrationOAuthService) private var oauthService
    @Injected(\.mcpServerManager) private var mcpServerManager
    @Injected(\.mcpOAuthService) private var mcpOAuthService
    @Injected(\.keychainService) private var keychainService
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var capabilitySelections: [CapabilityProviderSelection]
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]

    @State private var showRemoveConfirmation = false
    @State private var isReconnecting = false
    @State private var reconnectError: String?
    @State private var showingAulaReconnect = false
    @State private var showingIMAPReconnect = false
    @State private var partialGrantWarning: String?

    private var integration: Integration? {
        if case .builtin(let integration) = subject { integration } else { nil }
    }

    private var server: MCPServer? {
        if case .server(let server) = subject { server } else { nil }
    }

    private var type: IntegrationType? {
        integration.flatMap { BundledIntegrationType.type(forID: $0.typeID) }
    }

    private var displayName: String {
        switch subject {
        case .builtin(let integration):
            type?.displayName ?? integration.typeID
        case .server(let server):
            server.name
        }
    }

    /// What it gives you, said once under the name.
    private var kindLabel: String? {
        switch subject {
        case .builtin:
            Localized.Integration.Screen.kindLabel
        case .server:
            nil
        }
    }

    private var needsReconnect: Bool {
        switch subject {
        case .builtin(let integration):
            IntegrationHealthMonitor.shared.needsReconnect(
                integration,
                oauthService: oauthService
            )
        case .server(let server):
            mcpServerManager.connectionErrors[server.id] != nil
        }
    }

    private var connectionState: ConnectionState {
        switch subject {
        case .builtin:
            needsReconnect ? .attention : .connected
        case .server(let server):
            if !server.isEnabled {
                .disabled
            } else {
                needsReconnect ? .attention : .connected
            }
        }
    }

    private var statusLabel: String {
        switch connectionState {
        case .attention: Localized.Integration.Screen.Status.reconnectNeeded
        case .disabled: Localized.Mcp.Status.disabled
        default: Localized.Integration.Screen.Status.connected
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: displayName,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            AppAnchoredScrollView {
                VStack(spacing: Sizing.PageLayout.gap) {
                    AppIdentityHeader(
                        name: displayName,
                        kind: kindLabel,
                        state: connectionState,
                        status: statusLabel,
                        icon: markImage,
                        letter: markImage == nil ? String(displayName.prefix(1)) : nil
                    )

                    if let notice { notice }

                    facts

                    if let capabilityRows {
                        AppRowsGroup(
                            label: Localized.Integration.Screen.activeLabel,
                            rows: capabilityRows
                        )
                    }

                    offers

                    // The reconnect button is the only section worth
                    // anchoring: on a server with few tools, an unconditional
                    // spacer leaves the remove group dangling far below with
                    // nothing to justify the gap.
                    if needsReconnect {
                        Spacer(minLength: 0)

                        ReconnectButton(isReconnecting: isReconnecting) {
                            reconnect()
                        }

                        if let reconnectError {
                            Text(reconnectError)
                                .typography(Typography.tag)
                                .foregroundStyle(colors.text.standard.error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    removeGroup
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .alert(
            Localized.Integration.Screen.removeTitle(displayName),
            isPresented: $showRemoveConfirmation
        ) {
            Button(Localized.Integrations.Action.disconnect, role: .destructive) { remove() }
            Button(Localized.Common.Actions.cancel, role: .cancel) {}
        } message: {
            Text(removeWarning)
        }
        .alert(
            Localized.Ui.integrations,
            isPresented: Binding(
                get: { partialGrantWarning != nil },
                set: { if !$0 { partialGrantWarning = nil } }
            )
        ) {
            Button(Localized.Common.Actions.ok) {}
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

    // MARK: - Mark

    private var markImage: Image? {
        switch subject {
        case .builtin(let integration):
            BundledIntegrationType.type(forID: integration.typeID)?.brandImage
        case .server:
            nil
        }
    }

    // MARK: - Notice

    /// The notice raises the problem; the Reconnect button below answers it.
    /// A plain outage gets no button: there is nothing to press.
    private var notice: AppNotice? {
        switch subject {
        case .builtin(let integration) where needsReconnect:
            AppNotice(
                tone: .warning,
                title: Localized.Integration.Screen.Notice.expiredTitle,
                body: Localized.Integration.Screen.Notice.expiredBody(displayName)
            )
        case .server(let server):
            if let error = mcpServerManager.connectionErrors[server.id] {
                AppNotice(
                    tone: .error,
                    title: Localized.Integration.Screen.Notice.serverTitle,
                    body: error
                )
            } else {
                nil
            }
        default:
            nil
        }
    }

    // MARK: - Facts

    private var facts: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Integration.Screen.Facts.connectsVia,
                    value: connectsVia,
                    accessory: .none
                ),
                addressRow,
            ]
        )
    }

    /// The mechanism is a fact here, not a kind of screen.
    private var connectsVia: String {
        switch subject {
        case .builtin:
            Localized.Integration.Screen.viaBuiltin
        case .server:
            Localized.Integration.Screen.viaServer
        }
    }

    private var addressRow: AppRowSpec {
        switch subject {
        case .builtin(let integration):
            AppRowSpec(
                title: Localized.Common.Fields.account,
                value: integration.accountLabel,
                accessory: .none
            )
        case .server(let server):
            AppRowSpec(
                title: Localized.Integration.Screen.Facts.address,
                value: server.url,
                accessory: .none
            )
        }
    }

    // MARK: - Capability selection

    /// Where the capability's active choice now lives. A capability with more
    /// than one connected provider needs an explicit pick; this screen shows
    /// whether it is this one.
    private var providedCapabilities: [Capability] {
        guard let integration else { return [] }
        let granted = Set(integration.grantedCapabilities)
        return (type?.providedCapabilities.filter { granted.contains($0.rawValue) } ?? [])
            .sorted { $0.rawValue < $1.rawValue }
    }

    private var capabilityRows: [AppRowSpec]? {
        guard let integration else { return nil }
        let rows: [AppRowSpec] = providedCapabilities
            .filter { providers(for: $0).count > 1 }
            .map { capability in
                AppRowSpec(
                    id: capability.rawValue,
                    title: Localized.Integration.Screen.activeForRow(
                        capability.displayName
                    ),
                    trailing: .toggle(
                        isOn: isActiveProvider(for: capability),
                        isDisabled: false,
                        action: { setActiveProvider(for: capability) }
                    )
                )
            }
        return rows.isEmpty ? nil : rows
    }

    private func providers(for capability: Capability) -> [Integration] {
        integrations.filter { integration in
            integration.isEnabled
                && Set(integration.grantedCapabilities).contains(capability.rawValue)
        }
    }

    private func isActiveProvider(for capability: Capability) -> Bool {
        integrationManager.activeIntegration(
            for: capability,
            integrations: integrations,
            selections: capabilitySelections
        )?.id == integration?.id
    }

    private func setActiveProvider(for capability: Capability) {
        guard let integration else { return }
        if isActiveProvider(for: capability) {
            // Stepping down hands the capability to the next-connected
            // provider, which is what the manager would fall back to anyway.
            guard let next = providers(for: capability).first(where: { $0.id != integration.id })
            else { return }
            integrationManager.setActiveProvider(next, for: capability, in: modelContext)
        } else {
            integrationManager.setActiveProvider(integration, for: capability, in: modelContext)
        }
        Haptics.light()
    }

    // MARK: - Offers

    /// What it can actually do, capped like any other long list. A busy
    /// server offers twenty tools, which would bury everything under it.
    @ViewBuilder
    private var offers: some View {
        switch subject {
        case .builtin(let integration):
            capabilitiesGroup(integration)
        case .server(let server):
            toolsGroup(server)
        }
    }

    private var offerLimit: Int {
        5
    }

    @ViewBuilder
    private func capabilitiesGroup(_ integration: Integration) -> some View {
        let granted = Set(integration.grantedCapabilities)
        let all = (type?.providedCapabilities ?? Set(
            integration.grantedCapabilities.compactMap(Capability.init)
        ))
        let entries = all
            .sorted { $0.rawValue < $1.rawValue }
            .map { ($0, granted.contains($0.rawValue)) }

        // A single capability that is granted needs no list, and checkmarks
        // on every row say nothing the row titles don't: the group only
        // earns its place when there is a real set to compare, or something
        // was not granted and the footnote has to say so.
        let partial = entries.contains { !$1 }
        if entries.count > 1 || partial {
            AppRowsGroup(
                label: Localized.Integration.Screen.offersLabel,
                footnote: partial ? Localized.Integration.Screen.partialFootnote : nil,
                rows: entries.map { capability, _ in
                    AppRowSpec(
                        id: capability.rawValue,
                        title: capability.displayName,
                        accessory: .none
                    )
                }
            )
        }
    }

    @ViewBuilder
    private func toolsGroup(_ server: MCPServer) -> some View {
        let tools = server.cachedToolNames
        if tools.isEmpty {
            AppRowsGroup(
                label: Localized.Mcp.tools,
                rows: [
                    AppRowSpec(
                        title: Localized.Mcp.noToolsDiscovered,
                        accessory: .none
                    ),
                ]
            )
        } else {
            // Same shape as the models list on a provider screen: the first
            // few with hairlines between them, then a way to the rest.
            let capped = Array(tools.prefix(offerLimit))
            AppContentGroup(
                label: Localized.Mcp.tools,
                footnote:
                tools.count > capped.count
                    ? Localized.Integration.Screen.toolsFootnote("\(tools.count)")
                    : nil
            ) {
                ForEach(Array(capped.enumerated()), id: \.element) { index, tool in
                    if index > 0 { RowHairline() }
                    AppRow(
                        AppRowSpec(id: tool, title: tool.titleCased, accessory: .none)
                    )
                }
                if tools.count > capped.count {
                    RowHairline()
                    NavigationLink {
                        OffersScreen(
                            items: tools.map { $0.titleCased },
                            noun: Localized.Mcp.tools
                        )
                        .hidesTabBar()
                    } label: {
                        AppRow(
                            AppRowSpec(
                                title: Localized.Integration.Screen.showAllTools("\(tools.count)"),
                                tone: .muted
                            )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Remove

    private var removeWarning: String {
        switch subject {
        case .builtin:
            Localized.Integration.Screen.removeWarning
        case .server:
            Localized.Mcp.removeWarning
        }
    }

    private var removeGroup: some View {
        AppRowsGroup(
            rows: [
                AppRowSpec(
                    title: Localized.Integration.Screen.remove(displayName),
                    accessory: .trash,
                    tone: .destructive,
                    action: { showRemoveConfirmation = true }
                ),
            ]
        )
    }

    private func remove() {
        switch subject {
        case .builtin(let integration):
            integrationManager.disconnect(integration)
            // Fall back to the next connected provider for any capability
            // this integration was the explicit active choice for.
            integrationManager.clearSelections(referencing: integration.id, in: modelContext)
            modelContext.delete(integration)
        case .server(let server):
            for suffix in MCPServer.keychainSuffixes {
                keychainService.delete(
                    key: keychainService.mcpKey(for: server.id, suffix: suffix)
                )
            }
            modelContext.delete(server)
        }
        dismiss()
    }

    // MARK: - Reconnect

    private func reconnect() {
        guard let integration else {
            reauthorizeMCP()
            return
        }
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
        guard let integration else { return }
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
                    partialGrantWarning = IntegrationCopy.partialGrant(
                        accountLabel: result.accountLabel,
                        ungranted: ungranted
                    )
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

    /// An OAuth server that stops answering mid-session gets its tokens
    /// refreshed in place.
    private func reauthorizeMCP() {
        guard let server, let serverURL = URL(string: server.url) else { return }
        isReconnecting = true
        reconnectError = nil

        Task {
            do {
                let config = try await mcpOAuthService.discoverOAuth(for: serverURL)
                if let config {
                    _ = try await mcpOAuthService.authorize(config: config, serverID: server.id)
                } else {
                    // Server is now open — clear tokens and reconnect.
                    mcpOAuthService.clearTokens(for: server.id)
                    await mcpServerManager.disconnect(serverID: server.id)
                }
                isReconnecting = false
            } catch MCPOAuthError.userCancelled {
                isReconnecting = false
            } catch {
                reconnectError = error.localizedDescription
                isReconnecting = false
            }
        }
    }
}

// MARK: - Reconnect button

/// The screen's answer to an amber notice: find the primary action here.
private struct ReconnectButton: View {
    let isReconnecting: Bool
    let action: () -> Void

    var body: some View {
        if isReconnecting {
            AppButton(Localized.Integrations.Action.reconnect, variant: .primary) {}
                .disabled(true)
                .overlay { ProgressView() }
        } else {
            AppButton(Localized.Integrations.Action.reconnect, variant: .primary, action: action)
        }
    }
}

#Preview("Google") {
    let integration = Integration(
        typeID: "google",
        accountLabel: "daniel@gmail.com",
        grantedCapabilities: [Capability.email.rawValue]
    )
    return NavigationStack {
        IntegrationScreen(subject: .builtin(integration))
    }
    .previewEnvironment { $0.insert(integration) }
}

#Preview("Partial grant") {
    let integration = Integration(
        typeID: "google",
        accountLabel: "daniel@gmail.com",
        grantedCapabilities: []
    )
    return NavigationStack {
        IntegrationScreen(subject: .builtin(integration))
    }
    .previewEnvironment { $0.insert(integration) }
}
