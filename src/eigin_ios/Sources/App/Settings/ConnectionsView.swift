import Factory
import SwiftData
import SwiftUI

/// The connections hub: two questions, not four mechanisms.
///
/// Providers are where the thinking happens; integrations are everything
/// Eigin can reach on your behalf. Whether an integration is built in, an MCP
/// server or another agent is a fact on its own screen, not a group in this
/// list, so there is one place to look and one way to add. Descriptions say
/// what a connection gives you; only a connection that needs something from
/// you carries a status.
struct ConnectionsView: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Injected(\.integrationOAuthService) private var oauthService
    @Injected(\.integrationManager) private var integrationManager
    @Injected(\.mcpServerManager) private var mcpServerManager
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @Query(sort: \Integration.createdAt) private var integrations: [Integration]
    @State private var showSelectSheet = false
    @State private var showConnectSheet = false
    @State private var selectedMode: ProviderConnectSheetContent.Mode?
    @State private var showAddIntegration = false
    /// The connect sheet stacks over the add sheet, as provider connect does
    /// over provider select.
    @State private var connectTarget: ConnectTarget?
    @Injected(\.gemmaModelManager) private var gemmaManager: any GemmaModelManaging
    @Injected(\.integrationHealthMonitor) private var healthMonitor

    private var localPreset: ProviderPreset? {
        ProviderPreset.all.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var cloudProviders: [Provider] {
        providers
            .filter { !ProviderPreset.isLocal($0.baseURL) && !ProviderPreset.isRelay($0.baseURL) }
    }

    private var connectedBaseURLs: [String] {
        providers.map(\.baseURL)
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
            ProviderSelectSheetContent(connectedBaseURLs: connectedBaseURLs) { selection in
                showSelectSheet = false
                switch selection {
                case .preset(let preset, let method):
                    selectedMode = .preset(preset, method: method)
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
            detents: [.large],
            fitsContent: true
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
        .appSheet(
            isPresented: $showAddIntegration,
            title: Localized.Integration.Add.title,
            description: Localized.Integration.Add.description,
            detents: [.large]
        ) {
            AddIntegrationSheetContent { target in
                showAddIntegration = false
                connectTarget = target
            }
        }
        .sheet(isPresented: Binding(
            get: { connectTarget != nil },
            set: { if !$0 { connectTarget = nil } }
        )) {
            if let target = connectTarget {
                ConnectIntegrationSheet(
                    target: target,
                    onConnected: {
                        Haptics.success()
                        connectTarget = nil
                    },
                    onCancelled: {
                        connectTarget = nil
                        showAddIntegration = true
                    }
                )
            }
        }
    }

    // MARK: - Providers

    /// The models Eigin thinks with.
    private var providersGroup: some View {
        AppContentGroup(label: Localized.Ui.aiProviders) {
            NavigationLink {
                EiginProviderView()
                    .hidesTabBar()
            } label: {
                AppRow(
                    AppRowSpec(
                        title: Localized.Provider.Eigin.title,
                        description: Localized.Provider.Eigin.rowSubtitle
                    )
                )
            }
            .buttonStyle(.plain)

            ForEach(cloudProviders) { provider in
                RowHairline()
                NavigationLink {
                    AiProviderScreen(provider: provider)
                        .hidesTabBar()
                } label: {
                    AppRow(providerRowSpec(provider))
                }
                .buttonStyle(.plain)
            }

            if let preset = localPreset, gemmaManager.isSupported {
                RowHairline()
                NavigationLink {
                    LocalProviderView(preset: preset)
                        .hidesTabBar()
                } label: {
                    AppRow(localRowSpec)
                }
                .buttonStyle(.plain)
            }

            RowHairline()
            AppRow(
                AppRowSpec(
                    id: "add-provider",
                    title: Localized.Settings.Action.addProvider,
                    accessory: .plus,
                    tone: .accent,
                    action: { showSelectSheet = true }
                )
            )
        }
    }

    private func providerRowSpec(_ provider: Provider) -> AppRowSpec {
        AppRowSpec(
            title: provider.name,
            description: Self.modelsDescription(provider.enabledModels.count)
        )
    }

    private var localRowSpec: AppRowSpec {
        AppRowSpec(
            title: Localized.Provider.Local.title,
            description: Localized.Provider.Local.kindLabel
        )
    }

    /// The count a person can act on: what appears in the agent tab now.
    private static func modelsDescription(_ count: Int) -> String {
        count == 1
            ? Localized.Provider.Description.Models.one("1")
            : Localized.Provider.Description.Models.other("\(count)")
    }

    // MARK: - Integrations

    /// Everything Eigin can reach on your behalf, in one list.
    private var integrationsGroup: some View {
        AppContentGroup(label: Localized.Ui.integrations) {
            ForEach(integrationSubjects) { subject in
                if subject.id != integrationSubjects.first?.id {
                    RowHairline()
                }
                NavigationLink {
                    IntegrationScreen(subject: subject)
                        .hidesTabBar()
                } label: {
                    AppRow(integrationRowSpec(subject))
                }
                .buttonStyle(.plain)
            }

            if !integrationSubjects.isEmpty {
                RowHairline()
            }
            AppRow(
                AppRowSpec(
                    id: "add-integration",
                    title: Localized.Settings.Action.addIntegration,
                    accessory: .plus,
                    tone: .accent,
                    action: { showAddIntegration = true }
                )
            )
        }
    }

    private var integrationSubjects: [IntegrationScreen.Subject] {
        var subjects: [IntegrationScreen.Subject] = integrations
            .filter(\.isEnabled)
            .map { .builtin($0) }
        subjects.append(contentsOf: mcpServers.map { .server($0) })
        return subjects
    }

    private func integrationRowSpec(_ subject: IntegrationScreen.Subject) -> AppRowSpec {
        switch subject {
        case .builtin(let integration):
            let type = BundledIntegrationType.type(forID: integration.typeID)
            let needsReconnect = healthMonitor.needsReconnect(
                integration,
                oauthService: oauthService
            )
            return AppRowSpec(
                id: integration.id.uuidString,
                title: type?.displayName ?? integration.typeID,
                description: integration.accountLabel,
                trailing: needsReconnect
                    ? .status(.attention, Localized.Integrations.Status.reconnectNeeded)
                    : nil
            )

        case .server(let server):
            let needsAttention = mcpServerManager
                .connectionErrors[server.id] != nil
            return AppRowSpec(
                id: server.id.uuidString,
                title: server.name,
                description: server.cachedToolNames.isEmpty
                    ? server.url
                    : "\(server.cachedToolNames.count) \(Localized.Mcp.tools)",
                trailing: needsAttention
                    ? .status(.attention, Localized.Integration.Screen.Status.reconnectNeeded)
                    : nil
            )
        }
    }

    // MARK: - Sheets

    private var connectSheetTitle: String {
        switch selectedMode {
        case .preset(let preset, _): preset.name
        case .custom: Localized.Provider.Connect.addressTitle
        case nil: ""
        }
    }

    private var connectSheetDescription: String? {
        switch selectedMode {
        case .preset(let preset, _): preset.helpText
        case .custom: Localized.Provider.Setup.Custom.apiRequirement
        case nil: nil
        }
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
