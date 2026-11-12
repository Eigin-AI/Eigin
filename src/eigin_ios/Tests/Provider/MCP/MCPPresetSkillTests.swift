@testable import Eigin
import Foundation
import MCP
import Testing

@Suite("MCP preset discovery")
struct MCPPresetSkillTests {
    @Test func discoversDineroWithoutAConnection() throws {
        let skill = try #require(SkillCatalog.skill(
            forID: MCPPreset.dinero.skillID,
            mcpServers: []
        ))
        #expect(skill.requiredTools.isEmpty)
        #expect(SkillCatalog.connectionNeeded(for: skill, connected: []) == "Dinero")
        #expect(skill.descriptor.contains("accounting"))
        #expect(IntegrationCatalogEntry.matching("Dinero", in: [.mcpPreset(.dinero)]).count == 1)
    }

    @Test func keepsOneStableSkillAndUsesServerInstructions() throws {
        let server = MCPServer(name: "Dinero", url: MCPPreset.dinero.endpoint.absoluteString)
        server.presetID = MCPPreset.dinero.id
        server.serverInstructions = "Use the latest accounting workflow."
        server.cachedToolNames = ["report"]
        let skills = MCPServerSkill.project(servers: [server])
        #expect(skills.count == 1)
        let skill = try #require(skills.first)
        #expect(skill.id == MCPPreset.dinero.skillID)
        #expect(skill.instruction.contains(MCPPreset.dinero.instructions))
        #expect(skill.instruction.contains("latest accounting workflow"))
        #expect(skill.connectionPresetID == nil)
        server.name = "My accounts"
        #expect(MCPServerSkill.server(forSkillID: skill.id, servers: [server])?.id == server.id)
        #expect(MCPServerSkill.skill(forID: skill.id, servers: [server])?.requiredTools == skill
            .requiredTools)
    }

    @Test func manualAndPresetConnectionsHaveIndependentTools() throws {
        let preset = MCPServer(name: "Dinero", url: MCPPreset.dinero.endpoint.absoluteString)
        preset.presetID = MCPPreset.dinero.id
        let manual = MCPServer(name: "Dinero", url: preset.url)
        preset.cachedToolNames = ["report"]
        manual.cachedToolNames = ["report"]
        let skills = MCPServerSkill.project(servers: [preset, manual])
        #expect(skills.count == 2)
        #expect(Set(skills.map(\.id)).count == 2)
        #expect(Set(skills.flatMap { $0.requiredTools.map(\.key) }).count == 2)
        #expect(MCPServerSkill.server(forSkillID: "mcp__dinero", servers: [preset, manual])?
            .id == manual.id)
        #expect(MCPServerSkill.skill(forID: MCPPreset.dinero.skillID, servers: [manual])?
            .connectionPresetID == "dinero")
        #expect(MCPServerSkill.server(forSkillID: MCPPreset.dinero.skillID, servers: [preset])?
            .id == preset.id)
        let connection = MCPServerConnection(
            serverName: preset.name, endpoint: MCPPreset.dinero.endpoint,
            authProvider: NoAuthProvider(), toolNamespace: preset.toolNamespace
        )
        let proxy = MCPToolProxy(
            mcpTool: MCP.Tool(
                name: "report",
                description: "Read a report",
                inputSchema: .object([:])
            ),
            serverName: preset.name, connection: connection
        )
        let skill = try #require(skills.first { $0.id == MCPPreset.dinero.skillID })
        #expect(skill.requiredTools.map(\.key).contains(proxy.name))
    }

    @Test(arguments: [
        "get_account_balance", String(repeating: "a", count: 64),
        String(repeating: "a", count: 63) + "b", "reports.balance", "kontoplan_æøå",
    ])
    func toolDefinitionsFitProviderLimits(remoteName: String) throws {
        let server = MCPServer(name: "Dinero", url: MCPPreset.dinero.endpoint.absoluteString)
        server.presetID = MCPPreset.dinero.id
        server.cachedToolNames = [remoteName]
        let connection = MCPServerConnection(
            serverName: server.name, endpoint: MCPPreset.dinero.endpoint,
            authProvider: NoAuthProvider(), toolNamespace: server.toolNamespace
        )
        let proxy = MCPToolProxy(
            mcpTool: MCP.Tool(
                name: remoteName,
                description: "Read accounting",
                inputSchema: .object([:])
            ),
            serverName: server.name, connection: connection
        )
        let name = proxy.definition().function.name
        #expect(name.utf8.count <= 64)
        #expect(name.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil)
        let skill = try #require(SkillCatalog.skill(
            forID: MCPPreset.dinero.skillID,
            mcpServers: [server]
        ))
        #expect(skill.requiredTools.map(\.key).contains(name))
        let other = MCPNaming.toolName(
            serverName: server.toolNamespace,
            toolName: remoteName + "_other"
        )
        #expect(name != other)
    }

    @Test func disabledPresetNeedsApprovalAndHasNoTools() throws {
        let server = MCPServer(
            name: "Dinero",
            url: MCPPreset.dinero.endpoint.absoluteString,
            isEnabled: false
        )
        server.presetID = "dinero"
        server.cachedToolNames = ["report"]
        let skill = try #require(SkillCatalog.skill(
            forID: MCPPreset.dinero.skillID,
            mcpServers: [server]
        ))
        #expect(skill.connectionPresetID == "dinero")
        #expect(skill.requiredTools.isEmpty)
        #expect(SkillCatalog.resolvable(from: [skill], connectedCapabilities: []).isEmpty)
    }
}
