import SwiftUI

struct AgentAdvanced: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss
    @Bindable var agent: Agent

    var body: some View {
        SoftEdgeScrollView {
            VStack(spacing: Sizing.PageLayout.gap) {
                coreCard
                behaviourCard
            }
            .padding(.horizontal, Spacing.n16)
        } header: {
            AppNavigationHeader(
                title: Localized.Agent.Profile.Section.advanced,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: agent.identityCore) { agent.updatedAt = .now }
        .onChange(of: agent.userCore) { agent.updatedAt = .now }
        .onChange(of: agent.soulCore) { agent.updatedAt = .now }
    }

    // MARK: - Core documents

    private var coreCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                coreDocumentRow(
                    title: Localized.Agent.identityLabel,
                    text: $agent.identityCore
                )
                Divider()
                    .padding(.leading, Spacing.n24)
                coreDocumentRow(
                    title: Localized.Agent.userLabel,
                    text: $agent.userCore
                )
                Divider()
                    .padding(.leading, Spacing.n24)
                coreDocumentRow(
                    title: Localized.Agent.soul,
                    text: $agent.soulCore
                )
            }
        }
    }

    private func coreDocumentRow(title: String, text: Binding<String>) -> some View {
        NavigationLink {
            DocumentEditor(title: title, text: text)
                .hidesTabBar()
        } label: {
            HStack(spacing: Spacing.n16) {
                Text(title)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Spacer()
                if !text.wrappedValue.isEmpty {
                    Text(text.wrappedValue.prefix(30) + (text.wrappedValue.count > 30 ? "…" : ""))
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                        .lineLimit(1)
                } else {
                    Text(Localized.Common.Placeholder.notSet)
                        .typography(Typography.tag)
                        .foregroundStyle(colors.text.standard.muted)
                }
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

    // MARK: - Behaviour

    private var behaviourCard: some View {
        AppCardSurface(padding: 0) {
            VStack(spacing: 0) {
                NavigationLink {
                    KnowledgeContainer(agentID: agent.id)
                        .hidesTabBar()
                } label: {
                    behaviourRow(title: Localized.Knowledge.sectionTitle)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, Spacing.n24)

                NavigationLink {
                    IntentsList(agentID: agent.id)
                        .hidesTabBar()
                } label: {
                    behaviourRow(title: Localized.Agent.intents)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, Spacing.n24)

                NavigationLink {
                    SkillsList()
                        .hidesTabBar()
                } label: {
                    behaviourRow(title: Localized.Agent.skills)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func behaviourRow(title: String) -> some View {
        HStack(spacing: Spacing.n16) {
            Text(title)
                .typography(Typography.titleXS)
                .foregroundStyle(colors.text.standard.base)
            Spacer()
            Image(systemName: "chevron.right")
                .typography(Typography.miniLabel)
                .foregroundStyle(colors.text.standard.muted)
        }
        .padding(.horizontal, Spacing.n24)
        .padding(.vertical, Spacing.n16)
        .contentShape(Rectangle())
    }
}
