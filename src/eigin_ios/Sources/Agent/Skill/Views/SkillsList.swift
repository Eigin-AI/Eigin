import SwiftUI

/// Lists all bundled skills the agent can use.
struct SkillsList: View {
    @Environment(\.colors) private var colors

    var body: some View {
        List(BundledSkill.all) { skill in
            NavigationLink {
                SkillDetail(skill: skill)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(skill.displayName)
                        .typography(Typography.headline)
                        .foregroundStyle(colors.textPrimary)
                    Text(skill.description)
                        .typography(Typography.caption)
                        .foregroundStyle(colors.textSecondary)
                }
            }
            .listRowBackground(colors.surface)
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(Localized.Agent.skills, style: Typography.largeTitle)
    }
}

#Preview {
    NavigationStack {
        SkillsList()
    }
    .previewEnvironment()
}
