import SwiftUI

struct AgentAdvanced: View {
    @Environment(\.colors) private var colors
    @Bindable var agent: Agent

    var body: some View {
        Form {
            Section {
                Group {
                    coreDocumentRow(
                        title: Localized.Agent.identityLabel,
                        icon: "person.text.rectangle",
                        color: .orange,
                        text: $agent.identityCore
                    )
                    coreDocumentRow(
                        title: Localized.Agent.userLabel,
                        icon: "person.fill",
                        color: .green,
                        text: $agent.userCore
                    )
                    coreDocumentRow(
                        title: Localized.Agent.soul,
                        icon: "sparkles",
                        color: .indigo,
                        text: $agent.soulCore
                    )
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Agent.Profile.Section.core)
                    .typography(Typography.miniLabel)
            }

            Section {
                Group {
                    NavigationLink {
                        KnowledgeContainer(agentID: agent.id)
                            .hidesTabBar()
                    } label: {
                        HStack(spacing: Spacing.n8) {
                            SettingsIcon(systemName: "book.closed", color: .cyan)
                            Text(Localized.Knowledge.sectionTitle)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                        }
                    }

                    NavigationLink {
                        IntentsList(agentID: agent.id)
                            .hidesTabBar()
                    } label: {
                        HStack(spacing: Spacing.n8) {
                            SettingsIcon(systemName: "arrow.triangle.branch", color: .orange)
                            Text(Localized.Agent.intents)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                        }
                    }

                    NavigationLink {
                        SkillsList()
                            .hidesTabBar()
                    } label: {
                        HStack(spacing: Spacing.n8) {
                            SettingsIcon(systemName: "sparkles.rectangle.stack", color: .purple)
                            Text(Localized.Agent.skills)
                                .typography(Typography.navTab)
                                .foregroundStyle(colors.text.standard.base)
                        }
                    }
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Agent.Profile.Section.behaviour)
                    .typography(Typography.miniLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Agent.Profile.Section.advanced, style: Typography.titleXl)
        .onChange(of: agent.identityCore) { agent.updatedAt = .now }
        .onChange(of: agent.userCore) { agent.updatedAt = .now }
        .onChange(of: agent.soulCore) { agent.updatedAt = .now }
    }

    private func coreDocumentRow(
        title: String,
        icon: String,
        color: Color,
        text: Binding<String>
    ) -> some View {
        NavigationLink {
            DocumentEditor(title: title, text: text)
                .hidesTabBar()
        } label: {
            HStack(spacing: Spacing.n8) {
                SettingsIcon(systemName: icon, color: color)
                Text(title)
                    .typography(Typography.navTab)
                    .foregroundStyle(colors.text.standard.base)
                Spacer()
                Text(text.wrappedValue
                    .isEmpty ? Localized.Common.Placeholder
                    .notSet : String(text.wrappedValue.prefix(30)) + "...")
                    .foregroundStyle(colors.text.standard.muted)
                    .typography(Typography.note)
                    .lineLimit(1)
            }
        }
    }
}
