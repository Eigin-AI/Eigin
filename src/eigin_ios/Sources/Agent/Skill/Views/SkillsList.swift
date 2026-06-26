import SwiftUI

/// Lists all bundled skills the agent can use.
struct SkillsList: View {
    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: Localized.Agent.skills,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

            List(BundledSkill.all) { skill in
                NavigationLink {
                    SkillDetail(skill: skill)
                        .hidesTabBar()
                } label: {
                    VStack(alignment: .leading, spacing: Spacing.n4) {
                        Text(skill.displayName)
                            .typography(Typography.titleXS)
                            .foregroundStyle(colors.text.standard.base)
                        Text(skill.description)
                            .typography(Typography.miniLabel)
                            .foregroundStyle(colors.text.standard.muted)
                    }
                }
                .listRowBackground(colors.surface.standard.alternative)
            }
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        SkillsList()
    }
    .previewEnvironment()
}
