@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Verified MCP setup", .serialized)
@MainActor
struct MCPConnectionSaveTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(SchemaV15.models, version: SchemaV15.versionIdentifier),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func verified(temporaryID: UUID) -> MCPConnectionSave.VerifiedConnection {
        .init(
            name: "Dinero", url: "https://mcp.dinero.dk", authType: .oauth,
            toolNames: ["report"], instructions: "Current server guidance.",
            oauth: nil, temporaryID: temporaryID
        )
    }

    @Test func movesCredentialsAndReusesPresetAcrossSetupFlows() throws {
        let container = try container()
        let keychain = DefaultKeychainService(serviceKey: "preset-test.\(UUID().uuidString)")
        let firstID = UUID()
        let secondID = UUID()
        defer {
            for server in (try? container.mainContext.fetch(FetchDescriptor<MCPServer>())) ?? [] {
                MCPConnectionSave.discard(temporaryID: server.id, keychain: keychain)
            }
            MCPConnectionSave.discard(temporaryID: firstID, keychain: keychain)
            MCPConnectionSave.discard(temporaryID: secondID, keychain: keychain)
        }
        keychain.save(key: keychain.mcpKey(for: firstID, suffix: "access_token"), value: "first")
        let server = try MCPConnectionSave.save(
            verified(temporaryID: firstID), preset: .dinero, context: container.mainContext,
            keychain: keychain
        )
        #expect(keychain.read(key: keychain.mcpKey(for: firstID, suffix: "access_token")) == nil)
        #expect(keychain
            .read(key: keychain.mcpKey(for: server.id, suffix: "access_token")) == "first")
        keychain.save(key: keychain.mcpKey(for: secondID, suffix: "access_token"), value: "second")
        let repeated = try MCPConnectionSave.save(
            verified(temporaryID: secondID), preset: .dinero, context: container.mainContext,
            keychain: keychain
        )
        #expect(repeated.id == server.id)
        #expect(try container.mainContext.fetch(FetchDescriptor<MCPServer>()).count == 1)
        #expect(keychain
            .read(key: keychain.mcpKey(for: server.id, suffix: "access_token")) == "first")
        #expect(keychain.read(key: keychain.mcpKey(for: secondID, suffix: "access_token")) == nil)
        let skill = try #require(SkillCatalog.skill(
            forID: MCPPreset.dinero.skillID,
            mcpServers: [server]
        ))
        #expect(skill.instruction.contains("Current server guidance."))
    }

    @Test func manualSetupStaysSeparateAndDisabledPresetKeepsItsIdentity() throws {
        let container = try container()
        let keychain = PreviewKeychainService()
        let manual = try MCPConnectionSave.save(
            verified(temporaryID: UUID()), preset: nil, context: container.mainContext,
            keychain: keychain
        )
        let preset = try MCPConnectionSave.save(
            verified(temporaryID: UUID()), preset: .dinero, context: container.mainContext,
            keychain: keychain
        )
        preset.isEnabled = false
        let enabled = try MCPConnectionSave.save(
            verified(temporaryID: UUID()), preset: .dinero, context: container.mainContext,
            keychain: keychain
        )
        #expect(enabled.id == preset.id)
        #expect(enabled.isEnabled)
        #expect(manual.presetID == nil)
        #expect(manual.id != enabled.id)
        #expect(try container.mainContext.fetch(FetchDescriptor<MCPServer>()).count == 2)
    }
}
