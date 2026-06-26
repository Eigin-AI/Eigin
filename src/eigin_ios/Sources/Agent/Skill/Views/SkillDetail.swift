import SwiftUI

/// Shows a skill's instruction and the tools it provides.
struct SkillDetail: View {
    let skill: Skill

    @Environment(\.colors) private var colors
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            AppNavigationHeader(
                title: skill.displayName,
                leading: {
                    AppActionButton(
                        icon: Iconography.Functional.Arrow.left,
                        variant: .open,
                        size: .medium,
                        action: { dismiss() }
                    )
                }
            )

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
        }
        .background(colors.surface.standard.base.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        SkillDetail(skill: BundledSkill.web)
    }
}
