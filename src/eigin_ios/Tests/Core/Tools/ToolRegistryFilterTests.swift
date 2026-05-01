@testable import Eigin
import Factory
import Foundation
import Testing

@Suite("ToolRegistry Filtering")
struct ToolRegistryFilterTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    // MARK: - Never tools are excluded

    @Test @MainActor func neverToolsAreExcludedFromRegistry() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .never],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let registry = ToolRegistry.chat(permissionPolicy: policy)
        let toolNames = registry.definitions.map(\.function.name)
        #expect(!toolNames.contains("edit_core"))
    }

    @Test @MainActor func allowedToolsRemainInRegistry() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .never],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let registry = ToolRegistry.chat(permissionPolicy: policy)
        let toolNames = registry.definitions.map(\.function.name)
        #expect(toolNames.contains("read_core"))
    }

    @Test @MainActor func askToolsAreNotExcluded() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let registry = ToolRegistry.chat(permissionPolicy: policy)
        let toolNames = registry.definitions.map(\.function.name)
        #expect(toolNames.contains("edit_core"))
    }

    @Test @MainActor func allNeverExcludesAllTools() {
        var grants = [String: ToolPermissionLevel]()
        for capability in ToolRegistry.allBuiltInCapabilities {
            grants[capability.key] = .never
        }
        let policy = AgentPermissionPolicy(
            builtInGrants: grants,
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        let registry = ToolRegistry.chat(permissionPolicy: policy)
        let toolNames = Set(registry.definitions.map(\.function.name))
        for capability in ToolRegistry.allBuiltInCapabilities {
            #expect(!toolNames.contains(capability.key))
        }
    }

    @Test @MainActor func noGrantsPreservesAllStandardTools() {
        let policy = AlwaysAllowPolicy()
        let filtered = ToolRegistry.chat(permissionPolicy: policy)
        let baseline = ToolRegistry.chat(permissionPolicy: AlwaysAllowPolicy())

        let filteredNames = Set(filtered.definitions.map(\.function.name))
        let baselineNames = Set(baseline.definitions.map(\.function.name))
        #expect(filteredNames == baselineNames)
    }
}
