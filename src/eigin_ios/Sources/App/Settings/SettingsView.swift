import Factory
import SwiftData
import SwiftUI

struct SettingsView: View {
    @Injected(\.languageManager) private var languageManager
    @Environment(\.colors) private var colors
    @Query(sort: \Agent.createdAt) private var agents: [Agent]
    @State private var showFeedbackSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AppNavigationHeader(title: Localized.Ui.settings, leading: { EmptyView() })

                ScrollView {
                    VStack(spacing: Sizing.PageLayout.gap) {
                        generalGroup
                        agentGroup
                        systemGroup
                    }
                    .padding(.horizontal, Spacing.n16)
                    .padding(.top, Spacing.n8)
                    .padding(.bottom, Spacing.n32)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .background(colors.surface.standard.base.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .tabBarPadding()
        }
        .ignoresSafeArea(.container, edges: .bottom)
        .appSheet(
            isPresented: $showFeedbackSheet,
            title: Localized.Settings.Feedback.sheetTitle,
            description: Localized.Settings.Feedback.formDescription,
            detents: [.large]
        ) {
            FeedbackFormContent()
        }
    }

    // MARK: - Groups

    private var generalGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.Section.general)

            VStack(spacing: 0) {
                languagePicker
                Divider().padding(.leading, Spacing.n24)
                feedbackRow
            }
            .background(colors.surface.standard.alternative)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card))
        }
    }

    private var agentGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.Section.agent)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    if let agent = agents.primary {
                        NavigationLink {
                            ToolPermissions(agent: agent)
                                .hidesTabBar()
                        } label: {
                            chevronRow(Localized.Settings.Label.permissions)
                        }
                        .buttonStyle(.plain)

                        Divider().padding(.leading, Spacing.n24)
                    }

                    NavigationLink {
                        ConnectionsView()
                            .hidesTabBar()
                    } label: {
                        chevronRow(Localized.Ui.connections)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var systemGroup: some View {
        VStack(spacing: Sizing.PageLayout.ContentGrouping.gap) {
            sectionLabel(Localized.Settings.Section.system)

            AppCardSurface(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink {
                        AdvancedSettings()
                            .hidesTabBar()
                    } label: {
                        chevronRow(Localized.Settings.Section.advanced)
                    }
                    .buttonStyle(.plain)

#if DEBUG
                    Divider().padding(.leading, Spacing.n24)

                    NavigationLink {
                        DevelopmentMenu()
                            .hidesTabBar()
                    } label: {
                        chevronRow(Localized.Settings.Section.development)
                    }
                    .buttonStyle(.plain)
#endif
                }
            }
        }
    }

    // MARK: - Rows

    private var languagePicker: some View {
        let binding = Binding(
            get: { languageManager.currentLanguage },
            set: { languageManager.setLanguage($0) }
        )

        return AppOptionPicker(
            title: Localized.Ui.language,
            options: AppLanguage.allCases.map { AppOption($0.displayName, value: $0) },
            selection: binding.wrappedValue
        ) { binding.wrappedValue = $0 }
    }

    private var feedbackRow: some View {
        Button { showFeedbackSheet = true } label: {
            HStack(spacing: Spacing.n16) {
                Text(Localized.Settings.Feedback.sendFeedback)
                    .typography(Typography.titleXS)
                    .foregroundStyle(colors.text.standard.base)
                Spacer()
            }
            .padding(.horizontal, Spacing.n24)
            .padding(.vertical, Spacing.n16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func chevronRow(_ title: String) -> some View {
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

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typography(Typography.miniLabel)
            .foregroundStyle(colors.text.standard.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.n8)
    }
}

#Preview {
    SettingsView()
        .previewEnvironment()
}
