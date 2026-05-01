@testable import Eigin
import Foundation
import Testing

@Suite("Permission Policies")
struct PermissionPolicyTests {
    // MARK: - AlwaysAllowPolicy

    @Test func alwaysAllowPolicyReturnsAlways() {
        let policy = AlwaysAllowPolicy()
        #expect(policy.permissionLevel(for: "read_core") == .always)
        #expect(policy.permissionLevel(for: "unknown_tool") == .always)
    }

    // MARK: - AgentPermissionPolicy — defaults

    @Test func defaultsToToolDefaultWhenNoGrant() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )

        // read_core defaults to .always
        #expect(policy.permissionLevel(for: "read_core") == .always)
        // edit_core defaults to .ask
        #expect(policy.permissionLevel(for: "edit_core") == .ask)
    }

    @Test func unknownToolWithNoCapabilitiesDefaultsToAsk() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [:],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "nonexistent_tool") == .ask)
    }

    // MARK: - AgentPermissionPolicy — agent grants override defaults

    @Test func agentGrantNeverOverridesAlwaysDefault() {
        // read_core defaults to .always — override to .never
        let policy = AgentPermissionPolicy(
            builtInGrants: [ReadCoreTool.capability.key: .never],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "read_core") == .never)
    }

    @Test func agentGrantAskOverridesAlwaysDefault() {
        // read_core defaults to .always — override to .ask
        let policy = AgentPermissionPolicy(
            builtInGrants: [ReadCoreTool.capability.key: .ask],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "read_core") == .ask)
    }

    @Test func agentGrantAlwaysOverridesAskDefault() {
        // edit_core defaults to .ask — override to .always
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .always],
            discoveredGrants: [:],
            chatGrants: [],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "edit_core") == .always)
    }

    // MARK: - AgentPermissionPolicy — chat grants

    @Test func chatGrantUpgradesAskToAlways() {
        // edit_core defaults to .ask — chat grant should upgrade to .always
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .ask],
            discoveredGrants: [:],
            chatGrants: [EditCoreTool.capability.key],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "edit_core") == .always)
    }

    @Test func chatGrantDoesNotUpgradeNever() {
        // Agent grant sets .never — chat grant should NOT override
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .never],
            discoveredGrants: [:],
            chatGrants: [EditCoreTool.capability.key],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "edit_core") == .never)
    }

    @Test func chatGrantDoesNotAffectAlreadyAllowed() {
        // read_core defaults to .always — chat grant is redundant but harmless
        let policy = AgentPermissionPolicy(
            builtInGrants: [EditCoreTool.capability.key: .always],
            discoveredGrants: [:],
            chatGrants: [ReadCoreTool.capability.key],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "read_core") == .always)
    }

    // MARK: - AgentPermissionPolicy — mixed grant levels

    @Test func mixedGrantsAcrossToolsAreIndependent() {
        let policy = AgentPermissionPolicy(
            builtInGrants: [
                ReadCoreTool.capability.key: .always,
                EditCoreTool.capability.key: .never,
                DeleteKnowledgeTool.capability.key: .ask,
            ],
            discoveredGrants: [:],
            chatGrants: [DeleteKnowledgeTool.capability.key],
            canPromptUser: true
        )
        #expect(policy.permissionLevel(for: "read_core") == .always)
        #expect(policy.permissionLevel(for: "edit_core") == .never)
        // delete_knowledge is .ask but has chat grant → .always
        #expect(policy.permissionLevel(for: "delete_knowledge") == .always)
    }
}
