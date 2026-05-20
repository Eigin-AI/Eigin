import Factory
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Injected(\.languageManager) private var languageManager
    @Environment(\.colors) private var colors
    @Query(sort: \Agent.createdAt) private var agents: [Agent]

    var body: some View {
        NavigationStack {
            List {
                generalSection
                agentSection
                systemSection
            }
            .scrollContentBackground(.hidden)
            .background(colors.surface.standard.base.ignoresSafeArea())
            .navigationTitle(Localized.Ui.settings, style: Typography.titleXl)
            .tabBarPadding()
        }
        .ignoresSafeArea(.container, edges: .bottom)
    }

    // MARK: - Sections

    private var generalSection: some View {
        Section {
            languagePicker
                .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.Section.general)
                .typography(Typography.miniLabel)
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

    private var agentSection: some View {
        Section {
            Group {
                if let agent = agents.first {
                    NavigationLink {
                        ToolPermissions(agent: agent)
                            .hidesTabBar()
                    } label: {
                        HStack(spacing: Spacing.n8) {
                            SettingsIcon(systemName: "lock.fill", color: .cyan)
                            Text(Localized.Settings.Label.permissions)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                        }
                    }
                }

                NavigationLink {
                    ConnectionsView()
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "link", color: .blue)
                        Text(Localized.Ui.connections)
                            .typography(Typography.navTab)
                            .foregroundStyle(colors.text.standard.base)
                    }
                }
            }
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.Section.agent)
                .typography(Typography.miniLabel)
        }
    }

    private var systemSection: some View {
        Section {
            Group {
                NavigationLink {
                    AdvancedSettings()
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "gearshape.2.fill", color: .gray)
                        Text(Localized.Settings.Section.advanced)
                            .typography(Typography.navTab)
                            .foregroundStyle(colors.text.standard.base)
                    }
                }

#if DEBUG
                NavigationLink {
                    DevelopmentMenu()
                        .hidesTabBar()
                } label: {
                    HStack(spacing: Spacing.n8) {
                        SettingsIcon(systemName: "hammer.fill", color: .orange)
                        Text(Localized.Settings.Section.development)
                            .typography(Typography.navTab)
                            .foregroundStyle(colors.text.standard.base)
                    }
                }
#endif
            }
            .listRowBackground(colors.surface.standard.alternative)
        } header: {
            Text(Localized.Settings.Section.system)
                .typography(Typography.miniLabel)
        }
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
