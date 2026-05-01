@testable import Eigin
import Factory
import Foundation
import Testing

@Suite("Skill Definitions")
struct SkillTests {
    // MARK: - BundledSkill catalog

    @Test func allBundledSkillsHaveRequiredFields() {
        for skill in BundledSkill.all {
            #expect(!skill.id.isEmpty, "Skill \(skill.id) has empty id")
            #expect(!skill.displayName.isEmpty, "Skill \(skill.id) has empty displayName")
            #expect(!skill.description.isEmpty, "Skill \(skill.id) has empty description")
            #expect(!skill.instruction.isEmpty, "Skill \(skill.id) has empty instruction")
            #expect(!skill.requiredTools.isEmpty, "Skill \(skill.id) has no required tools")
        }
    }

    @Test func bundledSkillIDsAreUnique() {
        let ids = BundledSkill.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func noToolCapabilityAppearsInMultipleSkills() {
        var seen = [String: String]() // capability key -> skill id
        for skill in BundledSkill.all {
            for tool in skill.requiredTools {
                if let existingSkill = seen[tool.key] {
                    Issue.record(
                        "Tool \(tool.key) appears in both \(existingSkill) and \(skill.id)"
                    )
                }
                seen[tool.key] = skill.id
            }
        }
    }

    @Test func lookupByIDFindsSkill() {
        let skill = BundledSkill.skill(forID: "knowledge")
        #expect(skill != nil)
        #expect(skill?.displayName == "Knowledge")
    }

    @Test func lookupByIDReturnsNilForUnknown() {
        #expect(BundledSkill.skill(forID: "nonexistent") == nil)
    }

    // MARK: - Skill identity

    @Test func skillEqualityIsBasedOnID() {
        let a = Skill(
            id: "test", displayName: "A", description: "A",
            instruction: "A", requiredTools: [], alwaysActive: false
        )
        let b = Skill(
            id: "test", displayName: "B", description: "B",
            instruction: "B", requiredTools: [], alwaysActive: true
        )
        #expect(a == b)
    }

    // MARK: - ToolRegistry skill filtering

    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    @Test @MainActor func registryWithSkillsOnlyIncludesSkillTools() async {
        // Use a controlled in-test skill rather than BundledSkill.alwaysActive
        // so the assertions don't drift when bundled skill membership changes.
        let policy = AlwaysAllowPolicy()
        let testSkill = Skill(
            id: "test-skill",
            displayName: "Test",
            description: "Test skill",
            instruction: "",
            requiredTools: [
                SearchKnowledgeTool.capability,
                AddKnowledgeTool.capability,
            ],
            alwaysActive: true
        )
        let registry = await ToolRegistry.chat(
            permissionPolicy: policy,
            activeSkills: [testSkill]
        )
        let toolNames = Set(registry.definitions.map(\.function.name))

        // The skill's required tools should be included.
        #expect(toolNames.contains("search_knowledge"))
        #expect(toolNames.contains("add_knowledge"))

        // Tools not required by any active skill should be filtered out.
        #expect(!toolNames.contains("web_search"))
        #expect(!toolNames.contains("compose_email"))
    }

    @Test @MainActor func registryWithAdditionalSkillIncludesUnion() async {
        let policy = AlwaysAllowPolicy()
        let activeSkills = BundledSkill.alwaysActive + [BundledSkill.web]
        let registry = await ToolRegistry.chat(
            permissionPolicy: policy,
            activeSkills: activeSkills
        )
        let toolNames = Set(registry.definitions.map(\.function.name))

        // Should include both always-active and web tools
        #expect(toolNames.contains("search_knowledge"))
        #expect(toolNames.contains("web_search"))
        #expect(toolNames.contains("web_fetch"))

        // Should still NOT include other on-demand tools
        #expect(!toolNames.contains("compose_email"))
    }

    @Test @MainActor func activateSkillToolAlwaysPresentWithSkills() async {
        let policy = AlwaysAllowPolicy()
        let registry = await ToolRegistry.chat(
            permissionPolicy: policy,
            activeSkills: BundledSkill.alwaysActive
        )
        let toolNames = Set(registry.definitions.map(\.function.name))

        // ActivateSkillTool is not in any skill's requiredTools but should be present
        #expect(toolNames.contains("activate_skill"))
    }

    @Test @MainActor func activateSkillToolPresentWithoutSkills() async {
        // When no skills are passed, skill filter doesn't apply — all tools present
        let policy = AlwaysAllowPolicy()
        let registry = await ToolRegistry.chat(
            permissionPolicy: policy
        )
        let toolNames = Set(registry.definitions.map(\.function.name))
        #expect(toolNames.contains("activate_skill"))
    }

    @Test @MainActor func neverPermissionOverridesSkillRequirement() async {
        let policy = AgentPermissionPolicy(
            builtInGrants: [WebSearchTool.capability.key: .never],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let registry = await ToolRegistry.chat(
            permissionPolicy: policy,
            activeSkills: BundledSkill.alwaysActive + [BundledSkill.web]
        )
        let toolNames = Set(registry.definitions.map(\.function.name))

        // web_fetch should be present but web_search should be blocked
        #expect(toolNames.contains("web_fetch"))
        #expect(!toolNames.contains("web_search"))
    }
}
