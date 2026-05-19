import SwiftUI

/// Lists all bundled skills the agent can use.
struct SkillsList: View {
    @Environment(\.colors) private var colors

    var body: some View {
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
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(Localized.Agent.skills, style: Typography.titleXl)
    }
}

#Preview {
    NavigationStack {
        SkillsList()
    }
    .previewEnvironment()
}
