@testable import Eigin
import Factory
import Foundation
import Testing

/// A minimal fake standing in for an ``MCPToolProxy`` instance, so gating can
/// be tested without a live MCP connection.
private struct FakeMCPTool: Tool {
    let name: String
    let displayName: String
    var capabilities: [ToolCapability] {
        [ToolCapability(
            kind: .discovered, key: name, displayName: displayName,
            defaultPermissionLevel: .ask, category: .external
        )]
    }

    var category: ToolCapability.Category {
        .external
    }

    var defaultPermissionLevel: ToolPermissionLevel {
        .ask
    }

    func definition() -> ToolDefinition {
        ToolDefinition(name: name, description: "fake", parameters: JSONSchema(type: "object"))
    }

    func execute(_ toolCall: ToolCall, agent: Agent) async -> ToolResult {
        ToolResult(toolCallID: toolCall.id, content: "", isError: false)
    }
}

@Suite("ToolAssembly MCP gating")
struct ToolAssemblyMCPGatingTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    private let toolName = "mcp__gitlab__list_issues"

    private func makeSkillAndTool() -> (Skill, any Tool) {
        let tool = FakeMCPTool(name: toolName, displayName: "GitLab: List Issues")
        let skill = Skill(
            id: "mcp__gitlab",
            displayName: "GitLab",
            description: "GitLab server",
            instruction: "Use GitLab tools.",
            requiredTools: [ToolCapability(
                kind: .discovered, key: toolName, displayName: "List Issues",
                defaultPermissionLevel: .ask, category: .external
            )],
            alwaysActive: false
        )
        return (skill, tool)
    }

    @Test @MainActor func mcpToolAbsentWhenServerSkillNotActive() {
        let (skill, tool) = makeSkillAndTool()
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: BundledSkill.alwaysActive,
            mcpTools: [tool],
            mcpSkills: [skill]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(!names.contains(toolName))
    }

    @Test @MainActor func mcpToolPresentWhenServerSkillActive() {
        let (skill, tool) = makeSkillAndTool()
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: BundledSkill.alwaysActive + [skill],
            mcpTools: [tool],
            mcpSkills: [skill]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(names.contains(toolName))
    }

    @Test @MainActor func otherServersToolsStayAbsentWhenOnlyOneActive() {
        let (activeSkill, activeTool) = makeSkillAndTool()
        let otherTool = FakeMCPTool(name: "mcp__linear__list_tickets", displayName: "Linear")
        let otherSkill = Skill(
            id: "mcp__linear",
            displayName: "Linear",
            description: "Linear server",
            instruction: "Use Linear tools.",
            requiredTools: [ToolCapability(
                kind: .discovered, key: "mcp__linear__list_tickets", displayName: "List Tickets",
                defaultPermissionLevel: .ask, category: .external
            )],
            alwaysActive: false
        )
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: BundledSkill.alwaysActive + [activeSkill],
            mcpTools: [activeTool, otherTool],
            mcpSkills: [activeSkill, otherSkill]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(names.contains(toolName))
        #expect(!names.contains("mcp__linear__list_tickets"))
    }
}
