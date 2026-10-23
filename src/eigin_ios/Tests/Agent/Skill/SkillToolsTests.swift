@testable import Eigin
import Testing

@Suite("Skill tool availability")
@MainActor
struct SkillToolsTests {
    private func manager() -> IntegrationManager {
        IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
    }

    @Test func connectedEmailUsesRealToolMetadataWithoutDuplicates() {
        let connections = ["google", "microsoft"].map {
            Integration(
                typeID: $0,
                accountLabel: "test@example.com",
                grantedCapabilities: ["email"]
            )
        }
        let tools = SkillTools.resolve(
            for: BundledSkill.email,
            integrations: connections,
            selections: [],
            manager: manager()
        )
        #expect(Set(tools.map(\.key)) == Set(EmailToolCapabilities.all.map(\.key)))
        #expect(tools.count == Set(tools.map(\.key)).count)
        #expect(tools
            .allSatisfy { ToolRegistry.capability(forKey: $0.key)?.displayName == $0.displayName })
    }

    @Test func disabledAndUngrantedConnectionsProvideNoTools() {
        let disabled = Integration(
            typeID: "google",
            accountLabel: "disabled@example.com",
            grantedCapabilities: ["email"],
            isEnabled: false
        )
        let ungranted = Integration(
            typeID: "microsoft",
            accountLabel: "ungranted@example.com",
            grantedCapabilities: []
        )
        let tools = SkillTools.resolve(
            for: BundledSkill.email,
            integrations: [disabled, ungranted],
            selections: [],
            manager: manager()
        )
        #expect(tools.isEmpty)
    }

    @Test func optionalConnectedToolsJoinTheBuiltInToolsOnlyWhenAvailable() {
        let manager = manager()
        let original = SkillTools.resolve(
            for: BundledSkill.planning,
            integrations: [],
            selections: [],
            manager: manager
        )
        #expect(Set(original) == BundledSkill.planning.requiredTools)
        let calendar = Integration(
            typeID: BundledIntegrationType.appleCalendar.id,
            accountLabel: "",
            grantedCapabilities: [Capability.calendar.rawValue]
        )
        let connected = SkillTools.resolve(
            for: BundledSkill.planning,
            integrations: [calendar],
            selections: [],
            manager: manager
        )
        let expected = BundledSkill.planning.requiredTools
            .union(BundledIntegrationType.appleCalendar.toolCapabilities)
        #expect(Set(connected) == expected)
        #expect(connected.count > original.count)
        calendar.isEnabled = false
        let disconnected = SkillTools.resolve(
            for: BundledSkill.planning,
            integrations: [calendar],
            selections: [],
            manager: manager
        )
        #expect(Set(disconnected) == BundledSkill.planning.requiredTools)
    }
}
