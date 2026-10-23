import Factory
import SwiftData
import SwiftUI

/// Bundled skills available through built-in tools and connected capabilities.
struct SkillsList: View {
    @Query private var integrations: [Integration]
    @Injected(\.integrationManager) private var integrationManager

    private var available: [Skill] {
        SkillCatalog.resolvable(
            from: BundledSkill.all,
            connectedCapabilities: integrationManager
                .connectedCapabilities(integrations: integrations)
        )
    }

    var body: some View {
        AppSecondaryScreen(title: Localized.Agent.skills) {
            AppContentGroup(
                label: Localized.Skills.available,
                footnote: Localized.Skills.footnote
            ) {
                ForEach(Array(available.enumerated()), id: \.element.id) { index, skill in
                    if index > 0 { RowHairline() }
                    NavigationLink {
                        SkillDetail(skill: skill).hidesTabBar()
                    } label: {
                        AppRow(AppRowSpec(title: skill.displayName, description: skill.description))
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#Preview {
    NavigationStack { SkillsList() }
        .previewEnvironment()
}
