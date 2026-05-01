import SwiftUI

/// Lists all bundled skills the agent can use.
struct SkillsList: View {
    var body: some View {
        List(BundledSkill.all) { skill in
            NavigationLink {
                SkillDetail(skill: skill)
            } label: {
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(skill.displayName)
                        .font(Typography.headline)
                    Text(skill.description)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(Localized.Agent.skills)
    }
}

#Preview {
    NavigationStack {
        SkillsList()
    }
}
