@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("IntegrationManager")
struct IntegrationManagerTests {
    @Test @MainActor func toolsByCapabilityEmptyWhenNoIntegrations() {
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        let map = manager.toolsByCapability(integrations: [], context: ToolContext())
        #expect(map.isEmpty)
    }

    @Test @MainActor func toolsByCapabilitySkipsDisabledIntegrations() {
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue],
            isEnabled: false
        )
        let map = manager.toolsByCapability(integrations: [integration], context: ToolContext())
        #expect(map[.email] == nil)
    }

    @Test @MainActor func toolsByCapabilitySkipsUngrantedCapabilities() {
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        // Connected, but the email capability wasn't part of the grant (e.g. a
        // future integration that only granted a different capability so far).
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: []
        )
        let map = manager.toolsByCapability(integrations: [integration], context: ToolContext())
        #expect(map[.email]?.isEmpty ?? true)
    }

    @Test @MainActor func toolsByCapabilityIncludesConnectedGrantedIntegration() {
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let map = manager.toolsByCapability(integrations: [integration], context: ToolContext())
        let names = Set((map[.email] ?? []).map(\.name))
        #expect(names.contains("email_list"))
        #expect(names.contains("email_send"))
    }

    @Test @MainActor func toolsByCapabilityKeepsOnlyTheFirstConnectedIntegrationPerCapability() {
        // AddIntegration already blocks connecting a second integration for an
        // already-provided capability, but toolsByCapability defends against it
        // too — two integrations granting `.email` must never both contribute
        // tools, since same-named tools would silently collide in ToolRegistry.
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        let first = Integration(
            typeID: "google", accountLabel: "first@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let second = Integration(
            typeID: "google", accountLabel: "second@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let map = manager.toolsByCapability(
            integrations: [first, second],
            context: ToolContext()
        )
        let emailTools = map[.email] ?? []
        let toolNames = emailTools.map(\.name)
        #expect(Set(toolNames).count == toolNames.count)
    }

    @Test @MainActor func isConnectedReflectsGrantAndEnabledState() {
        let manager = IntegrationManager(oauthService: FakeIntegrationOAuthService())
        let connected = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let disabled = Integration(
            typeID: "google", accountLabel: "b@gmail.com",
            grantedCapabilities: [Capability.email.rawValue], isEnabled: false
        )
        #expect(manager.isConnected(.email, integrations: [connected]))
        #expect(!manager.isConnected(.email, integrations: [disabled]))
        #expect(!manager.isConnected(.email, integrations: []))
    }
}
