import Factory
import SwiftData
import SwiftUI

struct ConnectionsView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Injected(\.keychainService) private var keychainService
    @Injected(\.integrationManager) private var integrationManager
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]
    @Query private var capabilitySelections: [CapabilityProviderSelection]
    @State private var showSelectSheet = false
    @State private var showConnectSheet = false
    @State private var selectedMode: ProviderConnectSheetContent.Mode?
    @State private var showingAddMCPServer = false
    @State private var showingAddIntegration = false
    @Bindable private var gemmaManager = GemmaModelManager.shared

    private var localPreset: ProviderPreset? {
        ProviderPreset.all.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var localProvider: Provider? {
        providers.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var cloudProviders: [Provider] {
        providers
            .filter { !ProviderPreset.isLocal($0.baseURL) && !ProviderPreset.isRelay($0.baseURL) }
    }

    private var connectSheetTitle: String {
        switch selectedMode {
        case .preset(let preset): preset.name
        case .custom: Localized.Provider.Picker.customProvider
        case nil: ""
        }
    }

    private var connectSheetDescription: String? {
        switch selectedMode {
        case .preset(let preset): preset.helpText
        case .custom: Localized.Provider.Setup.Custom.apiRequirement
        case nil: nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Ui.connections,
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
                    providersGroup
                    integrationsGroup
                    mcpServersGroup
                }
                .padding(.horizontal, Spacing.n16)
                .padding(.top, Spacing.n8)
                .padding(.bottom, Spacing.n32)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .appSheet(
            isPresented: $showSelectSheet,
            title: Localized.Provider.typeLabel,
            description: Localized.Onboarding.Provider.cloudExplanation,
            detents: [.large]
        ) {
            ProviderSelectSheetContent { selection in
                showSelectSheet = false
                switch selection {
                case .preset(let preset):
                    selectedMode = .preset(preset)
                case .custom:
                    selectedMode = .custom
                }
                showConnectSheet = true
            }
        }
        .appSheet(
            isPresented: $showConnectSheet,
            title: connectSheetTitle,
            description: connectSheetDescription,
            detents: [.large]
        ) {
            if let mode = selectedMode {
                ProviderConnectSheetContent(
                    mode: mode,
                    onComplete: { _ in
                        showConnectSheet = false
                        selectedMode = nil
                    },
                    onBack: {
                        showConnectSheet = false
                        selectedMode = nil
                        showSelectSheet = true
                    }
                )
            }
        }
        .sheet(isPresented: $showingAddMCPServer) {
            AddMCPServer()
        }
        .sheet(isPresented: $showingAddIntegration) {
            AddIntegration()
        }
    }

    // MARK: - Integrations

    /// Connected integrations grouped by the capability they were granted for,
    /// labeled with the capability's ``IntegrationCategory`` display name. An
    /// integration providing several capabilities appears in a section for each.
    private struct CapabilitySection: Identifiable {
        let capability: Capability
        let providers: [Integration]
        var id: Capability {
            capability
        }

        var sectionTitle: String {
            IntegrationCategory.category(for: capability)?.displayName ?? capability.rawValue
                .titleCased
        }
    }

    private var capabilitySections: [CapabilitySection] {
        var byCapability: [Capability: [Integration]] = [:]
        for integration in integrations where integration.isEnabled {
            guard let type = BundledIntegrationType.type(forID: integration.typeID)
            else { continue }
            let granted = type.providedCapabilities
                .filter { integration.grantedCapabilities.contains($0.rawValue) }
            for capability in granted {
                byCapability[capability, default: []].append(integration)
            }
        }
        return byCapability
            .map { capability, providers in
                CapabilitySection(
                    capability: capability,
                    providers: providers.sorted { $0.createdAt < $1.createdAt }
                )
            }
            .sorted { $0.capability.rawValue < $1.capability.rawValue }
    }

    private func activeIntegrationID(for section: CapabilitySection) -> UUID? {
        integrationManager.activeIntegration(
            for: section.capability,
            integrations: integrations,
            selections: capabilitySelections
        )?.id
    }

    /// One labeled card per category, followed by a single "Add Integration"
    /// action covering all of them.
    private var integrationsGroup: some View {
        VStack(spacing: Sizing.PageLayout.gap) {
            ForEach(capabilitySections) { section in
                VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
                    sectionLabel(section.sectionTitle)

                    AppCardSurface(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(
                                Array(section.providers.enumerated()),
                                id: \.element.id
                            ) { providerIndex, integration in
                                if providerIndex > 0 {
                                    Divider().padding(.leading, Spacing.n24)
                                }

                                integrationRow(
                                    integration,
                                    capability: section.capability,
                                    isActive: activeIntegrationID(for: section) == integration.id,
                                    showsSelector: section.providers.count > 1
                                )
                            }
                        }
                    }
                }
            }

            AppButton(
                Localized.Settings.Action.addIntegration,
                variant: .secondary,
                size: .medium,
                action: { showingAddIntegration = true },
                trailing: {
                    Image(systemName: "plus")
                        .typography(Typography.miniLabel)
                }
            )
        }
    }

    /// A single provider row for a capability section. The trailing radio
    /// (shown only when the capability has more than one provider) sets this
    /// integration as the active one for `capability` without navigating; the
    /// text area navigates to ``IntegrationDetail`` (remove/inspect).
    private func integrationRow(
        _ integration: Integration,
        capability: Capability,
        isActive: Bool,
        showsSelector: Bool
    ) -> some View {
        HStack(spacing: Spacing.n16) {
            if showsSelector {
                Button {
                    integrationManager.setActiveProvider(
                        integration,
                        for: capability,
                        in: modelContext
                    )
                } label: {
                    Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                        .typography(Typography.titleXS)
                        .foregroundStyle(isActive ? colors.accent : colors.text.standard.muted)
                }
                .buttonStyle(.plain)
            }

            NavigationLink {
                IntegrationDetail(integration: integration)
                    .hidesTabBar()
            } label: {
                HStack(spacing: Spacing.n16) {
                    VStack(alignment: .leading, spacing: Spacing.n4) {
                        Text(BundledIntegrationType.type(forID: integration.typeID)?
                            .displayName ?? integration.typeID)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(integration.accountLabel)
                            .typography(Typography.tag)
                            .foregroundStyle(colors.text.standard.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
    }

    // MARK: - Providers

    private var providersGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Ui.providers)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    // Eigin relay
                    NavigationLink {
                        EiginProviderView()
                            .hidesTabBar()
                    } label: {
                        providerRow(
                            name: "Eigin",
                            detail: Localized.Provider.Eigin.rowSubtitle
                        )
                    }
                    .buttonStyle(.plain)

                    // Cloud providers
                    ForEach(cloudProviders) { provider in
                        Divider().padding(.leading, Spacing.n24)

                        NavigationLink {
                            EditProvider(provider: provider)
                                .hidesTabBar()
                        } label: {
                            let count = provider.availableModels
                                .count(where: { KnownModelCatalog.lookup($0) != nil })
                            providerRow(
                                name: provider.name,
                                detail: Localized.Settings.Info.modelsAvailable("\(count)")
                            )
                        }
                        .buttonStyle(.plain)
                    }

                    // On-device model
                    if let preset = localPreset, gemmaManager.isSupported {
                        Divider().padding(.leading, Spacing.n24)

                        NavigationLink {
                            LocalProviderView(preset: preset)
                                .hidesTabBar()
                        } label: {
                            onDeviceRow
                        }
                        .buttonStyle(.plain)
                    }

                    Divider().padding(.leading, Spacing.n24)

                    // Add provider action
                    Button { showSelectSheet = true } label: {
                        HStack(spacing: Spacing.n16) {
                            Text(Localized.Settings.Action.addProvider)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.accent)
                            Spacer()
                            Image(systemName: "plus")
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.accent)
                        }
                        .padding(.horizontal, Spacing.n24)
                        .padding(.vertical, Spacing.n16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func providerRow(name: String, detail: String) -> some View {
        HStack(spacing: Spacing.n16) {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(name)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Text(detail)
                    .typography(Typography.tag)
                    .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
    }

    private var onDeviceRow: some View {
        HStack(spacing: Spacing.n16) {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(Localized.Provider.Picker.onDeviceModel)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Group {
                    switch gemmaManager.state {
                    case .notDownloaded, .failed:
                        Text(Localized.Settings.Info.modelNotDownloaded)
                    case .downloading:
                        Text(Localized.Settings.Info.modelDownloading)
                    case .downloaded, .compiling:
                        Text(Localized.Settings.Info.modelDownloaded)
                    case .ready:
                        let count = localProvider?.availableModels.count ?? 0
                        Text(Localized.Settings.Info.modelsAvailable("\(count)"))
                    }
                }
                .typography(Typography.tag)
                .foregroundStyle(colors.text.standard.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
    }

    // MARK: - MCP Servers

    private var mcpServersGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Ui.mcpServers)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(mcpServers.enumerated()), id: \.element.id) { index, server in
                        if index > 0 {
                            Divider().padding(.leading, Spacing.n24)
                        }

                        NavigationLink {
                            MCPServerDetail(server: server)
                                .hidesTabBar()
                        } label: {
                            mcpServerRow(server)
                        }
                        .buttonStyle(.plain)
                    }

                    if !mcpServers.isEmpty {
                        Divider().padding(.leading, Spacing.n24)
                    }

                    // Add MCP server action
                    Button { showingAddMCPServer = true } label: {
                        HStack(spacing: Spacing.n16) {
                            Text(Localized.Settings.Action.addMcpServer)
                                .typography(Typography.titleXS)
                                .foregroundStyle(colors.accent)
                            Spacer()
                            Image(systemName: "plus")
                                .typography(Typography.miniLabel)
                                .foregroundStyle(colors.accent)
                        }
                        .padding(.horizontal, Spacing.n24)
                        .padding(.vertical, Spacing.n16)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func mcpServerRow(_ server: MCPServer) -> some View {
        HStack(spacing: Spacing.n16) {
            VStack(alignment: .leading, spacing: Spacing.n4) {
                Text(server.name)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                if !server.cachedToolNames.isEmpty {
                    Text(verbatim: "\(server.cachedToolNames.count) \(Localized.Mcp.tools)")
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                } else {
                    Text(server.url)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
    }

    // MARK: - Helpers

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

#Preview("Connections — integrations connected") {
    NavigationStack {
        ConnectionsView()
    }
    .previewEnvironment(seed: PreviewIntegrations.seedConnected)
}

#Preview("Connections — no integrations") {
    NavigationStack {
        ConnectionsView()
    }
    .previewEnvironment()
}
