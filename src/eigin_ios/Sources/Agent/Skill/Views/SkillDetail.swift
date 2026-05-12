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
                    .listRowBackground(colors.surface)
            } header: {
                Text(Localized.Skills.instruction)
                    .typography(Typography.label)
            }

            Section {
                ForEach(
                    skill.requiredTools.sorted(by: { $0.displayName < $1.displayName }),
                    id: \.key
                ) { tool in
                    Label(tool.displayName, systemImage: "wrench")
                        .typography(Typography.subheadline)
                        .foregroundStyle(colors.textPrimary)
                }
                .listRowBackground(colors.surface)
            } header: {
                Text(Localized.Skills.tools)
                    .typography(Typography.label)
            }
        }
        .scrollContentBackground(.hidden)
        .background(colors.background.ignoresSafeArea())
        .navigationTitle(skill.displayName, style: Typography.largeTitle)
    }
}

#Preview {
    NavigationStack {
        SkillDetail(skill: BundledSkill.web)
    }
}
