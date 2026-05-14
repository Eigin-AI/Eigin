import Factory
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.themeManager) private var themeManager
    @Injected(\.languageManager) private var languageManager
    @Environment(\.colors) private var colors
    @Environment(\.modelContext) private var modelContext
    @Injected(\.keychainService) private var keychainService
    @Query(sort: \Agent.createdAt) private var agents: [Agent]
    @Query(sort: \Provider.createdAt) private var providers: [Provider]
    @Query(sort: \MCPServer.createdAt) private var mcpServers: [MCPServer]
    @State private var showingAddProvider = false
    @State private var showingAddMCPServer = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                appearanceSection
                securitySection
                providersSection
                mcpServersSection
                advancedSection
                developmentSection
            }
            .scrollContentBackground(.hidden)
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(Localized.Ui.settings, style: Typography.titleXl)
            .sheet(isPresented: $showingAddProvider) {
                ProviderPicker()
            }
            .sheet(isPresented: $showingAddMCPServer) {
                AddMCPServer()
            }
            .navigationDestination(for: PersistentIdentifier.self) { id in
                if let provider = providers.first(where: { $0.persistentModelID == id }) {
                    EditProvider(provider: provider, navigationPath: $navigationPath)
                } else if let server = mcpServers.first(where: { $0.persistentModelID == id }) {
                    MCPServerDetail(server: server)
                }
            }
        }
    }

    // MARK: - Sections

    private var appearanceSection: some View {
        Section {
            Group {
                themePicker
                languagePicker
            }
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.appearance)
                .typography(Typography.miniLabel)
        }
    }

    private var themePicker: some View {
        let binding = Binding(
            get: { themeManager.currentTheme.id },
            set: { newID in
                if let theme = ThemeManager.availableThemes
                    .first(where: { $0.id == newID })
                {
                    themeManager.selectTheme(theme)
                }
            }
        )

        return Picker(Localized.Ui.theme, selection: binding) {
            ForEach(ThemeManager.availableThemes, id: \.id) { theme in
                Text(theme.name).tag(theme.id)
            }
        }
    }

    private var languagePicker: some View {
        let binding = Binding(
            get: { languageManager.currentLanguage },
            set: { languageManager.setLanguage($0) }
        )

        return Picker(Localized.Ui.language, selection: binding) {
            ForEach(AppLanguage.allCases, id: \.self) { language in
                Text(language.displayName).tag(language)
            }
        }
    }

    @ViewBuilder
    private var securitySection: some View {
        if let agent = agents.first {
            Section {
                NavigationLink {
                    ToolPermissions(agent: agent)
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "lock.fill", color: .cyan)
                        Text(Localized.Settings.Label.permissions)
                            .typography(Typography.navTab)
                            .foregroundStyle(colors.text.standard.base)
                    }
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Ui.security)
                    .typography(Typography.miniLabel)
            }
        }
    }

    private var providersSection: some View {
        Section {
            ForEach(providers) { provider in
                NavigationLink(value: provider.persistentModelID) {
                    providerRow(provider)
                }
            }
            .onDelete(perform: deleteProviders)
            .listRowBackground(colors.surface.standard.alternative)

            Button(Localized.Settings.Action.addProvider) {
                showingAddProvider = true
            }
            .typography(Typography.navTab)
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Ui.providers)
                .typography(Typography.miniLabel)
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
                NavigationLink(value: server.persistentModelID) {
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

    private var advancedSection: some View {
        Section {
            NavigationLink {
                AdvancedSettings()
            } label: {
                HStack(spacing: Spacing.n8) {
                    SettingsIcon(systemName: "gearshape.2.fill", color: .gray)
                    Text(Localized.Settings.Section.advanced)
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.base)
                }
            }
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.Section.advanced)
                .typography(Typography.miniLabel)
        }
    }

    @ViewBuilder
    private var developmentSection: some View {
#if DEBUG
        Section {
            NavigationLink {
                DevelopmentMenu()
            } label: {
                HStack(spacing: Spacing.n8) {
                    SettingsIcon(systemName: "hammer.fill", color: .orange)
                    Text(Localized.Settings.Section.development)
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.base)
                }
            }
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.Section.development)
                .typography(Typography.miniLabel)
        }
#endif
    }

    private func deleteProviders(at offsets: IndexSet) {
        for index in offsets {
            let provider = providers[index]
            keychainService.delete(key: keychainService.providerKey(for: provider.id))

            if ProviderPreset.isLocal(provider.baseURL) {
                GemmaModelManager.shared.delete()
            }

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

#Preview {
    SettingsView()
        .previewEnvironment()
}
