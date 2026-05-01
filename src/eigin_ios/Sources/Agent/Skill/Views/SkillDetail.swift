import SwiftUI

/// Shows a skill's instruction and the tools it provides.
struct SkillDetail: View {
    let skill: Skill

    var body: some View {
        List {
            Section("Instruction") {
                Text(skill.instruction)
                    .font(Typography.body)
            }

            Section("Tools") {
                ForEach(
                    skill.requiredTools.sorted(by: { $0.displayName < $1.displayName }),
                    id: \.key
                ) { tool in
                    Label(tool.displayName, systemImage: "wrench")
                }
            }
        }
        .navigationTitle(skill.displayName)
    }
}

#Preview {
    NavigationStack {
        SkillDetail(skill: BundledSkill.web)
    }
}
