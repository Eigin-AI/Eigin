@testable import Eigin
import Factory
import Foundation
import Testing

/// Verifies the integrations gating rule: a tool from a connected integration
/// is only in the turn's tool set when an active skill declares the matching
/// capability.
@Suite("Integration Tool Resolution")
struct ToolResolutionTests {
    init() {
        Container.shared.reset()
        Container.shared.knowledgeService.register { PreviewKnowledgeService() }
        Container.shared.intentService.register { PreviewIntentService() }
    }

    private func emailTools() -> [any Tool] {
        EmailToolKit.tools(provider: FakeEmailProvider())
    }

    @Test @MainActor func integrationToolsAbsentWithoutActiveCapability() {
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: [],
            integrationToolsByCapability: [.email: emailTools()]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(!names.contains("email_list"))
    }

    @Test @MainActor func integrationToolsAbsentWhenNotConnected() {
        // Email skill active, but no integration tools supplied (nothing connected).
        // The skill has no base tools of its own, so activating it yields nothing —
        // AvailableSkillsSource keeps it out of the catalog in that case (see
        // SystemHintSourcesTests), but the resolution rule itself should still
        // behave correctly if it's somehow active anyway.
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: [BundledSkill.email],
            integrationToolsByCapability: [:]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(!names.contains("email_list"))
    }

    @Test @MainActor func integrationToolsPresentWhenSkillActiveAndConnected() {
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: [BundledSkill.email],
            integrationToolsByCapability: [.email: emailTools()]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(names.contains("email_list"))
        #expect(names.contains("email_search"))
        #expect(names.contains("email_read"))
        #expect(names.contains("email_send"))
        #expect(names.contains("email_reply"))
    }

    @Test @MainActor func integrationToolsAbsentWhenOtherSkillActive() {
        // Connected, but the active skill doesn't declare the email capability.
        let registry = ToolRegistry.chat(
            permissionPolicy: AlwaysAllowPolicy(),
            activeSkills: [BundledSkill.selfModification],
            integrationToolsByCapability: [.email: emailTools()]
        )
        let names = Set(registry.definitions.map(\.function.name))
        #expect(!names.contains("email_list"))
    }
}
