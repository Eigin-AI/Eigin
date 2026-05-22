import Factory
import SwiftData
import SwiftUI

struct ConnectionsView: View {
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Injected(\.keychainService) private var keychainService
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @State private var showSelectSheet = false
    @State private var showConnectSheet = false
    @State private var selectedMode: ProviderConnectSheetContent.Mode?
    @State private var showingAddMCPServer = false
    @Bindable private var gemmaManager = GemmaModelManager.shared

    private var localPreset: ProviderPreset? {
        ProviderPreset.all.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var localProvider: Provider? {
        providers.first { ProviderPreset.isLocal($0.baseURL) }
    }

    private var cloudProviders: [Provider] {
        providers.filter { !ProviderPreset.isLocal($0.baseURL) }
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
        List {
            providersSection
            mcpServersSection
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Ui.connections, style: Typography.titleXl)
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
    }

    private var providersSection: some View {
        Section {
            ForEach(cloudProviders) { provider in
                NavigationLink {
                    EditProvider(provider: provider)
                        .hidesTabBar()
                } label: {
                    providerRow(provider)
                }
            }
            .onDelete(perform: deleteCloudProviders)
            .listRowBackground(colors.surface.standard.alternative)

            if let preset = localPreset {
                NavigationLink {
                    LocalProviderView(preset: preset)
                        .hidesTabBar()
                } label: {
                    onDeviceRow
                }
                .listRowBackground(colors.surface.standard.alternative)
            }

            Button(Localized.Settings.Action.addProvider) {
                showSelectSheet = true
            }
            .typography(Typography.navTab)
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Ui.providers)
                .typography(Typography.miniLabel)
        }
    }

    private var onDeviceRow: some View {
        HStack(spacing: Spacing.n8) {
            VStack(alignment: .leading) {
                Text(Localized.Provider.Picker.onDeviceModel)
                    .typography(Typography.navTab)
                switch gemmaManager.state {
                case .notDownloaded, .failed:
                    Text(Localized.Settings.Info.modelNotDownloaded)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                case .downloading:
                    Text(Localized.Settings.Info.modelDownloading)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                case .downloaded, .compiling:
                    Text(Localized.Settings.Info.modelDownloaded)
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                case .ready:
                    let count = localProvider?.availableModels.count ?? 0
                    Text(Localized.Settings.Info.modelsAvailable("\(count)"))
                        .typography(Typography.miniLabel)
                        .foregroundStyle(colors.text.standard.muted)
                }
            }
        }
    }

    private func providerRow(_ provider: Provider) -> some View {
        VStack(alignment: .leading) {
            Text(provider.name)
                .typography(Typography.navTab)
            let count = provider.availableModels
                .count(where: { KnownModelCatalog.lookup($0) != nil })
            Text(Localized.Settings.Info.modelsAvailable("\(count)"))
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
    }

    private var mcpServersSection: some View {
        Section {
            ForEach(mcpServers) { server in
                NavigationLink {
                    MCPServerDetail(server: server)
                        .hidesTabBar()
                } label: {
                    MCPServerRow(server: server)
                }
            }
            .onDelete(perform: deleteMCPServers)
            .listRowBackground(colors.surface.standard.alternative)

            Button(Localized.Settings.Action.addMcpServer) {
                showingAddMCPServer = true
            }
            .typography(Typography.navTab)
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Ui.mcpServers)
                .typography(Typography.miniLabel)
        }
    }

    private func deleteCloudProviders(at offsets: IndexSet) {
        let targets = cloudProviders
        for index in offsets {
            let provider = targets[index]
            keychainService.delete(key: keychainService.providerKey(for: provider.id))
            modelContext.delete(provider)
        }
    }

    private func deleteMCPServers(at offsets: IndexSet) {
        for index in offsets {
            let server = mcpServers[index]
            for suffix in MCPServer.keychainSuffixes {
                keychainService.delete(key: keychainService.mcpKey(for: server.id, suffix: suffix))
            }
            modelContext.delete(server)
        }
    }
}
