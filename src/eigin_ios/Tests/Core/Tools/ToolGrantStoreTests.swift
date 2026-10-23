@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("Tool grant persistence")
@MainActor
struct ToolGrantStoreTests {
    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: AgentToolGrant.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func policy(in context: ModelContext, agentID: UUID) throws -> AgentPermissionPolicy {
        let rows = try context.fetch(FetchDescriptor<AgentToolGrant>())
            .filter { $0.agentID == agentID }
        return AgentPermissionPolicy(
            builtInGrants: Dictionary(uniqueKeysWithValues: rows.filter { $0.kind == .builtIn }
                .map { (
                    $0.key,
                    $0.level
                ) }),
            discoveredGrants: Dictionary(uniqueKeysWithValues: rows
                .filter { $0.kind == .discovered }.map { (
                    $0.key,
                    $0.level
                ) }),
            chatGrants: [], canPromptUser: true
        )
    }

    @Test func defaultRemovesOverrideAndRestoresSharedPermissionAfterReload() throws {
        let container = try container()
        let id = UUID()
        let store = ToolGrantStore(context: container.mainContext, agentID: id)
        let name = MCPNaming.toolName(serverName: "Home Assistant", toolName: "get_state")
        try store.set(MCPToolProxy.defaultCapability, level: .always)
        try store.setDiscovered(toolName: name, level: .never)
        #expect(try policy(in: ModelContext(container), agentID: id)
            .permissionLevel(for: name) == .never)
        try store.setDiscovered(toolName: name, level: nil)
        let reloaded = ModelContext(container)
        #expect(try policy(in: reloaded, agentID: id).permissionLevel(for: name) == .always)
        #expect(try reloaded.fetch(FetchDescriptor<AgentToolGrant>())
            .allSatisfy { $0.kind != .discovered })
        try store.set(MCPToolProxy.defaultCapability, level: .never)
        #expect(try policy(in: ModelContext(container), agentID: id)
            .permissionLevel(for: name) == .never)
    }

    @Test func explicitAskIsAnOverrideAndRepeatedChangesDoNotDuplicateRows() throws {
        let container = try container()
        let id = UUID()
        let store = ToolGrantStore(context: container.mainContext, agentID: id)
        let name = "mcp__home__get_state"
        try store.set(MCPToolProxy.defaultCapability, level: .always)
        for level in [ToolPermissionLevel.never, .always, .ask] {
            try store.setDiscovered(toolName: name, level: level)
        }
        let context = ModelContext(container)
        #expect(try policy(in: context, agentID: id).permissionLevel(for: name) == .ask)
        #expect(try context.fetch(FetchDescriptor<AgentToolGrant>())
            .count(where: { $0.kind == .discovered }) == 1)
    }

    @Test func resettingBuiltInDefaultKeepsOtherAgentsAndGrantKinds() throws {
        let container = try container()
        let id = UUID()
        let otherID = UUID()
        let cap = try #require(ToolRegistry.capability(forKey: "read_core"))
        let store = ToolGrantStore(context: container.mainContext, agentID: id)
        try store.set(cap, level: .never)
        try store.setDiscovered(toolName: cap.key, level: .never)
        try ToolGrantStore(context: container.mainContext, agentID: otherID).set(cap, level: .never)
        try store.set(cap, level: cap.defaultPermissionLevel)
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<AgentToolGrant>())
        #expect(rows.count == 2)
        #expect(rows.contains { $0.agentID == otherID && $0.kind == .builtIn })
        #expect(rows.contains { $0.agentID == id && $0.kind == .discovered })
    }

    @Test func failedWriteRestoresPermissionAndKeepsOtherEdits() throws {
        let container = try container()
        let context = container.mainContext
        let id = UUID()
        let name = "mcp__home__get_state"
        let store = ToolGrantStore(context: context, agentID: id)
        try store.setDiscovered(toolName: name, level: .never)
        let other = AgentToolGrant(
            agentID: UUID(),
            capability: MCPToolProxy.defaultCapability,
            level: .always
        )
        context.insert(other)
        var saves = 0
        let failingStore = ToolGrantStore(context: context, agentID: id, save: { context in
            saves += 1
            if saves == 2 { throw CocoaError(.fileWriteOutOfSpace) }
            try context.save()
        })
        #expect(throws: (any Error).self) { try failingStore.setDiscovered(
            toolName: name,
            level: nil
        ) }
        #expect(try policy(in: context, agentID: id).permissionLevel(for: name) == .never)
        #expect(try policy(in: ModelContext(container), agentID: id)
            .permissionLevel(for: name) == .never)
        #expect(try context.fetch(FetchDescriptor<AgentToolGrant>())
            .contains { $0.agentID == other.agentID && $0.level == .always })
        #expect(!context.hasChanges)
    }
}
