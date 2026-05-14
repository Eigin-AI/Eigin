import SwiftUI

/// Shows a skill's instruction and the tools it provides.
struct SkillDetail: View {
    let skill: Skill

    @Environment(\.colors) private var colors

    var body: some View {
        List {
            Section {
                Text(skill.instruction)
                    .typography(Typography.body)
                    .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Skills.instruction)
                    .typography(Typography.miniLabel)
            }

            Section {
                ForEach(
                    skill.requiredTools.sorted(by: { $0.displayName < $1.displayName }),
                    id: \.key
                ) { tool in
                    Label(tool.displayName, systemImage: "wrench")
                        .typography(Typography.navTab)
                        .foregroundStyle(colors.text.standard.base)
                }
                .listRowBackground(colors.surface.standard.alternative)
            } header: {
                Text(Localized.Skills.tools)
                    .typography(Typography.miniLabel)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.surface.standard.base.ignoresSafeArea())
        .navigationTitle(skill.displayName, style: Typography.titleXl)
    }
}

#Preview {
    NavigationStack {
        SkillDetail(skill: BundledSkill.web)
    }
}
