@testable import Eigin
import Foundation
import SwiftData
import Testing

@Suite("IntegrationManager")
struct IntegrationManagerTests {
    /// Keeping the container alive matters: `ModelContext` doesn't retain it,
    /// so an unretained container can be deallocated out from under a context
    /// that's still in use, crashing on the next fetch.
    @MainActor
    private func makeContext() throws -> (ModelContext, ModelContainer) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Schema(SchemaV5.models, version: SchemaV5.versionIdentifier),
            configurations: config
        )
        return (container.mainContext, container)
    }

    @Test @MainActor func toolsByCapabilityEmptyWhenNoIntegrations() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let map = manager.toolsByCapability(
            integrations: [],
            selections: [],
            context: ToolContext()
        )
        #expect(map.isEmpty)
    }

    @Test @MainActor func toolsByCapabilitySkipsDisabledIntegrations() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue],
            isEnabled: false
        )
        let map = manager.toolsByCapability(
            integrations: [integration], selections: [], context: ToolContext()
        )
        #expect(map[.email] == nil)
    }

    @Test @MainActor func toolsByCapabilitySkipsUngrantedCapabilities() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        // Connected, but the email capability wasn't part of the grant (e.g. a
        // future integration that only granted a different capability so far).
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: []
        )
        let map = manager.toolsByCapability(
            integrations: [integration], selections: [], context: ToolContext()
        )
        #expect(map[.email]?.isEmpty ?? true)
    }

    @Test @MainActor func toolsByCapabilityIncludesConnectedGrantedIntegration() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let integration = Integration(
            typeID: "google",
            accountLabel: "test@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let map = manager.toolsByCapability(
            integrations: [integration], selections: [], context: ToolContext()
        )
        let names = Set((map[.email] ?? []).map(\.name))
        #expect(names.contains("email_list"))
        #expect(names.contains("email_send"))
    }

    @Test @MainActor func toolsByCapabilityKeepsOnlyTheFirstConnectedIntegrationPerCapability() {
        // AddIntegration already blocks connecting a second integration for an
        // already-provided capability, but toolsByCapability defends against it
        // too — two integrations granting `.email` must never both contribute
        // tools, since same-named tools would silently collide in ToolRegistry.
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
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
            selections: [],
            context: ToolContext()
        )
        let emailTools = map[.email] ?? []
        let toolNames = emailTools.map(\.name)
        #expect(Set(toolNames).count == toolNames.count)
    }

    @Test @MainActor func toolsByCapabilityKeepsOnlyTheFirstConnectedIntegrationAcrossDifferentProviders() {
        // Google and Microsoft both provide `.email` — whichever was connected
        // first wins by default, and disconnecting it lets the other take over.
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let earlierDate = Date(timeIntervalSince1970: 0)
        let laterDate = Date(timeIntervalSince1970: 1000)
        let google = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        google.createdAt = earlierDate
        let microsoft = Integration(
            typeID: "microsoft", accountLabel: "a@outlook.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        microsoft.createdAt = laterDate

        // Both connected: only the earlier-created integration's five tools
        // contribute — not both providers' tools stacked (which would be 10
        // same-named tools colliding in `ToolRegistry`).
        let bothConnected = manager.toolsByCapability(
            integrations: [google, microsoft],
            selections: [],
            context: ToolContext()
        )
        #expect((bothConnected[.email] ?? []).count == 5)

        // Disconnecting the winner (drop it from the integrations list) lets
        // the remaining provider take over.
        let microsoftOnly = manager.toolsByCapability(
            integrations: [microsoft],
            selections: [],
            context: ToolContext()
        )
        let names = Set((microsoftOnly[.email] ?? []).map(\.name))
        #expect(names == ["email_list", "email_search", "email_read", "email_send", "email_reply"])
    }

    // MARK: - activeIntegration / provider selection

    @Test @MainActor func activeIntegrationPrefersExplicitSelection() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let google = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        google.createdAt = Date(timeIntervalSince1970: 0)
        let microsoft = Integration(
            typeID: "microsoft", accountLabel: "a@outlook.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        microsoft.createdAt = Date(timeIntervalSince1970: 1000)

        // Oldest (google) would win by default, but an explicit selection for
        // microsoft overrides that.
        let selection = CapabilityProviderSelection(
            capability: .email,
            integrationID: microsoft.id
        )
        let active = manager.activeIntegration(
            for: .email,
            integrations: [google, microsoft],
            selections: [selection]
        )
        #expect(active?.id == microsoft.id)
    }

    @Test @MainActor func activeIntegrationFallsBackWhenSelectionIsStale() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let google = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        google.createdAt = Date(timeIntervalSince1970: 0)
        let microsoft = Integration(
            typeID: "microsoft", accountLabel: "a@outlook.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        microsoft.createdAt = Date(timeIntervalSince1970: 1000)

        // Selection points at an integration that's no longer in the connected
        // list (e.g. disconnected) -> falls back to the oldest granted+enabled.
        let disconnectedID = UUID()
        let staleSelection = CapabilityProviderSelection(
            capability: .email,
            integrationID: disconnectedID
        )
        let active = manager.activeIntegration(
            for: .email,
            integrations: [google, microsoft],
            selections: [staleSelection]
        )
        #expect(active?.id == google.id)

        // Selection with a non-integration source kind is likewise ignored.
        let nativeSelection = CapabilityProviderSelection(
            capability: .email,
            sourceKind: .native,
            integrationID: microsoft.id
        )
        let activeWithNative = manager.activeIntegration(
            for: .email,
            integrations: [google, microsoft],
            selections: [nativeSelection]
        )
        #expect(activeWithNative?.id == google.id)
    }

    @Test @MainActor func activeIntegrationDefaultsToOldestWithoutSelection() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let google = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        google.createdAt = Date(timeIntervalSince1970: 1000)
        let microsoft = Integration(
            typeID: "microsoft", accountLabel: "a@outlook.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        microsoft.createdAt = Date(timeIntervalSince1970: 0)

        let active = manager.activeIntegration(
            for: .email,
            integrations: [google, microsoft],
            selections: []
        )
        #expect(active?.id == microsoft.id)
    }

    @Test @MainActor func setActiveProviderUpsertsSelection() throws {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let (context, _container) = try makeContext()
        let google = Integration(
            typeID: "google", accountLabel: "a@gmail.com",
            grantedCapabilities: [Capability.email.rawValue]
        )
        let microsoft = Integration(
            typeID: "microsoft", accountLabel: "a@outlook.com",
            grantedCapabilities: [Capability.email.rawValue]
        )

        manager.setActiveProvider(google, for: .email, in: context)
        var selections = try context.fetch(FetchDescriptor<CapabilityProviderSelection>())
        #expect(selections.count == 1)
        #expect(selections.first?.integrationID == google.id)

        // Selecting a different provider for the same capability updates the
        // existing row rather than inserting a second one.
        manager.setActiveProvider(microsoft, for: .email, in: context)
        selections = try context.fetch(FetchDescriptor<CapabilityProviderSelection>())
        #expect(selections.count == 1)
        #expect(selections.first?.integrationID == microsoft.id)
    }

    @Test @MainActor func clearSelectionsRemovesOnlyMatchingRows() throws {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
        let (context, _container) = try makeContext()
        let removedID = UUID()
        let keptID = UUID()
        context.insert(CapabilityProviderSelection(capability: .email, integrationID: removedID))
        // A hypothetical second capability's selection pointing elsewhere
        // should survive clearing `removedID`.
        let unrelated = CapabilityProviderSelection(capability: .email, integrationID: keptID)
        unrelated.capabilityRaw = "other"
        context.insert(unrelated)

        manager.clearSelections(referencing: removedID, in: context)

        let remaining = try context.fetch(FetchDescriptor<CapabilityProviderSelection>())
        #expect(remaining.count == 1)
        #expect(remaining.first?.integrationID == keptID)
    }

    @Test @MainActor func isConnectedReflectsGrantAndEnabledState() {
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore()
        )
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

    @Test @MainActor func disconnectClearsBothOAuthTokensAndIMAPCredentials() {
        let oauthService = FakeIntegrationOAuthService()
        let imapCredentialStore = FakeIMAPCredentialStore()
        let manager = IntegrationManager(
            oauthService: oauthService,
            imapCredentialStore: imapCredentialStore,
            aulaCredentialStore: FakeAulaCredentialStore(),
            declines: DeclinedCapabilities(defaults: .isolated())
        )
        let integration = Integration(
            typeID: "imap", accountLabel: "me@example.com",
            grantedCapabilities: [Capability.email.rawValue]
        )

        manager.disconnect(integration)

        #expect(oauthService.clearedIDs == [integration.id])
        #expect(imapCredentialStore.clearedIDs == [integration.id])
    }

    @Test @MainActor func removingAnIntegrationDeclinesWhatItProvided() {
        let declines = DeclinedCapabilities(defaults: .isolated())
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore(),
            declines: declines
        )
        let integration = Integration(
            typeID: "apple-health", accountLabel: "",
            grantedCapabilities: [Capability.health.rawValue]
        )

        manager.disconnect(integration)

        #expect(declines.isDeclined(.health))
        #expect(!declines.isDeclined(.email))
    }

    @Test @MainActor func connectingAPlatformIntegrationRecordsItOnceAndClearsANo() throws {
        let (context, container) = try makeContext()
        _ = container
        let declines = DeclinedCapabilities(defaults: .isolated())
        declines.decline(.health)
        let manager = IntegrationManager(
            oauthService: FakeIntegrationOAuthService(),
            imapCredentialStore: FakeIMAPCredentialStore(),
            aulaCredentialStore: FakeAulaCredentialStore(),
            declines: declines
        )

        manager.connectPlatform(BundledIntegrationType.appleHealth, in: context)
        manager.connectPlatform(BundledIntegrationType.appleHealth, in: context)

        let rows = try context.fetch(FetchDescriptor<Integration>())
        #expect(rows.count == 1)
        #expect(manager.isConnected(.health, integrations: rows))
        #expect(!declines.isDeclined(.health))
    }
}
