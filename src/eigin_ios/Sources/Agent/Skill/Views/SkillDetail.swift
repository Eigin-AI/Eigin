import Factory
import SwiftData
import SwiftUI

/// A skill's full instructions and the tools provided by its active connections.
struct SkillDetail: View {
    let skill: Skill
    @Query private var integrations: [Integration]
    @Query private var selections: [CapabilityProviderSelection]
    @Injected(\.integrationManager) private var integrationManager

    private var tools: [ToolCapability] {
        SkillTools.resolve(
            for: skill,
            integrations: integrations,
            selections: selections,
            manager: integrationManager
        )
    }

    var body: some View {
        AppSecondaryScreen(title: skill.displayName) {
            AppContentGroup(label: Localized.Skills.instruction) {
                AppDetailText(text: skill.instruction)
            }
            if !tools.isEmpty {
                AppRowsGroup(label: Localized.Skills.tools, rows: tools.map { tool in
                    AppRowSpec(id: tool.key, title: tool.displayName, accessory: .none)
                })
            }
        }
    }
}

#Preview {
    NavigationStack { SkillDetail(skill: BundledSkill.web) }
        .previewEnvironment()
}
