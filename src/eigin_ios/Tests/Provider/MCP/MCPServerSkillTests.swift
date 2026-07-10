@testable import Eigin
import Foundation
import Testing

@Suite("MCPServerSkill Projection")
struct MCPServerSkillTests {
    private func makeServer(
        name: String,
        isEnabled: Bool = true,
        toolNames: [String] = [],
        instructions: String? = nil
    ) -> MCPServer {
        let server = MCPServer(name: name, url: "https://example.com/mcp", isEnabled: isEnabled)
        server.cachedToolNames = toolNames
        server.serverInstructions = instructions
        return server
    }

    @Test func projectsOneSkillPerEnabledServer() {
        let servers = [
            makeServer(name: "GitLab", toolNames: ["list_issues", "create_issue"]),
            makeServer(name: "Linear", toolNames: ["list_tickets"]),
        ]
        let skills = MCPServerSkill.project(servers: servers)
        #expect(skills.count == 2)
        #expect(skills.map(\.id).sorted() == ["mcp__gitlab", "mcp__linear"])
    }

    @Test func skipsDisabledServers() {
        let servers = [
            makeServer(name: "GitLab", isEnabled: false),
            makeServer(name: "Linear", isEnabled: true),
        ]
        let skills = MCPServerSkill.project(servers: servers)
        #expect(skills.count == 1)
        #expect(skills.first?.id == "mcp__linear")
    }

    @Test func doesNotRequireAConnection() {
        // A server that has never connected (empty cache) still projects — the
        // catalog is cache-driven, not connection-driven.
        let server = makeServer(name: "Never Connected")
        let skills = MCPServerSkill.project(servers: [server])
        #expect(skills.count == 1)
        #expect(skills.first?.requiredTools.isEmpty == true)
    }

    @Test func requiredToolsMatchNamespacedCachedToolNames() throws {
        let server = makeServer(name: "GitLab", toolNames: ["list_issues"])
        let skill = try #require(MCPServerSkill.project(servers: [server]).first)
        let keys = Set(skill.requiredTools.map(\.key))
        #expect(keys.contains(MCPNaming.toolName(serverName: "GitLab", toolName: "list_issues")))
    }

    @Test func instructionFallsBackWhenServerProvidesNone() throws {
        let server = makeServer(name: "GitLab")
        let skill = try #require(MCPServerSkill.project(servers: [server]).first)
        #expect(!skill.instruction.isEmpty)
    }

    @Test func instructionUsesServerProvidedText() throws {
        let server = makeServer(name: "GitLab", instructions: "Use this to manage issues.")
        let skill = try #require(MCPServerSkill.project(servers: [server]).first)
        #expect(skill.instruction == "Use this to manage issues.")
    }

    @Test func disambiguatesCollidingNames() {
        let a = makeServer(name: "Notes")
        let b = makeServer(name: "Notes")
        let skills = MCPServerSkill.project(servers: [a, b])
        #expect(skills.count == 2)
        #expect(Set(skills.map(\.id)).count == 2)
        #expect(skills.map(\.id).contains("mcp__notes"))
    }

    @Test func serverForSkillIDResolvesBack() throws {
        let server = makeServer(name: "GitLab")
        let servers = [server]
        let skill = try #require(MCPServerSkill.project(servers: servers).first)
        let resolved = MCPServerSkill.server(forSkillID: skill.id, servers: servers)
        #expect(resolved?.id == server.id)
    }

    @Test func skillForIDReturnsNilForUnknown() {
        #expect(MCPServerSkill.skill(forID: "mcp__nonexistent", servers: []) == nil)
    }

    @Test func alwaysActiveIsFalseAndNoCapabilitiesRequired() throws {
        let server = makeServer(name: "GitLab")
        let skill = try #require(MCPServerSkill.project(servers: [server]).first)
        #expect(!skill.alwaysActive)
        #expect(skill.requiredCapabilities.isEmpty)
    }
}
