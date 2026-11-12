@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("MCP preset migration", .serialized)
@MainActor
struct MCPPresetMigrationTests {
    private func seed(at url: URL) throws {
        let container = try ModelContainer(
            for: Schema(SchemaV14.models, version: SchemaV14.versionIdentifier),
            configurations: ModelConfiguration(url: url)
        )
        let server = SchemaV6.MCPServer(name: "Dinero", url: "https://mcp.dinero.dk")
        server.cachedToolNames = ["report"]
        container.mainContext.insert(server)
        try container.mainContext.save()
    }

    @Test func preservesManualConnectionWithoutAssociatingPreset() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("store")
        try seed(at: url)
        let container = try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            migrationPlan: EiginMigrationPlan.self,
            configurations: ModelConfiguration(url: url)
        )
        let servers = try container.mainContext.fetch(FetchDescriptor<MCPServer>())
        let server = try #require(servers.first)
        #expect(server.presetID == nil)
        #expect(server.cachedToolNames == ["report"])
        #expect(MCPServerSkill.server(forSkillID: "mcp__dinero", servers: servers)?.id == server.id)
        #expect(MCPServerSkill
            .server(forSkillID: MCPPreset.dinero.skillID, servers: servers) == nil)
    }
}
