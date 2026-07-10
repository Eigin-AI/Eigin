import Factory
import Foundation
import SwiftData

/// Turns connected, enabled ``Integration`` records into tools grouped by
/// ``Capability``, for ``ToolAssembly`` to gate behind active skills.
///
/// Unlike ``MCPServerManager``, there's no live connection to manage — tool
/// construction is synchronous, since ``EmailProvider`` (and future backends)
/// fetch tokens lazily per-call rather than at connect time.
@MainActor
final class IntegrationManager {
    private let oauthService: any IntegrationOAuthService
    private let imapCredentialStore: any IMAPCredentialStore

    init(oauthService: any IntegrationOAuthService, imapCredentialStore: any IMAPCredentialStore) {
        self.oauthService = oauthService
        self.imapCredentialStore = imapCredentialStore
    }

    /// Builds the capability → tools map for all connected, enabled integrations,
    /// restricted to capabilities each integration actually had granted — the
    /// same rule ``connectedCapabilities(integrations:)`` uses, so the two never
    /// disagree about what a given integration provides. When more than one
    /// integration provides a capability, `selections` decides which one is
    /// active (see ``activeIntegration(for:integrations:selections:)``).
    func toolsByCapability(
        integrations: [Integration],
        selections: [CapabilityProviderSelection],
        context: ToolContext
    ) -> [Capability: [any Tool]] {
        var map: [Capability: [any Tool]] = [:]
        for capability in Capability.allCases {
            guard let integration = activeIntegration(
                for: capability,
                integrations: integrations,
                selections: selections
            ), let type = BundledIntegrationType.type(forID: integration.typeID)
            else { continue }
            map[capability] = type.makeTools(capability, integration, context)
        }
        return map
    }

    /// The integration that should serve `capability`, honoring an explicit
    /// selection when it's still valid (connected, enabled, and actually
    /// granted that capability), and otherwise falling back to the
    /// oldest-connected granted+enabled provider — the same default used
    /// before selection existed, so a fresh connection or a cleared selection
    /// never leaves a capability unexpectedly unserved.
    ///
    /// A selection whose `sourceKind` isn't `.integration` (i.e. a reserved
    /// `.native` row) is treated as no explicit choice, so it can never break
    /// tool assembly.
    func activeIntegration(
        for capability: Capability,
        integrations: [Integration],
        selections: [CapabilityProviderSelection]
    ) -> Integration? {
        let candidates = integrations
            .filter { $0.isEnabled }
            .compactMap { integration -> (Integration, IntegrationType)? in
                guard let type = BundledIntegrationType.type(forID: integration.typeID),
                      grantedCapabilities(of: integration, type: type).contains(capability)
                else { return nil }
                return (integration, type)
            }
            .map(\.0)
            .sorted { $0.createdAt < $1.createdAt }

        if let selection = selections.first(where: { $0.capability == capability }),
           selection.sourceKind == .integration,
           let selectedID = selection.integrationID,
           let selected = candidates.first(where: { $0.id == selectedID })
        {
            return selected
        }

        return candidates.first
    }

    /// Whether at least one connected, enabled integration provides `capability`.
    func isConnected(_ capability: Capability, integrations: [Integration]) -> Bool {
        connectedCapabilities(integrations: integrations).contains(capability)
    }

    /// All capabilities provided by at least one connected, enabled integration.
    func connectedCapabilities(integrations: [Integration]) -> Set<Capability> {
        var result: Set<Capability> = []
        for integration in integrations where integration.isEnabled {
            guard let type = BundledIntegrationType.type(forID: integration.typeID)
            else { continue }
            result.formUnion(grantedCapabilities(of: integration, type: type))
        }
        return result
    }

    /// Disconnects an integration: clears its stored credentials (OAuth
    /// tokens or, for IMAP, the stored server settings/password) and removes
    /// the model. Both clears are unconditional — whichever one doesn't apply
    /// to this integration's auth kind is simply a no-op against an empty
    /// Keychain entry. Callers are responsible for deleting `integration` from
    /// the model context and calling ``clearSelections(referencing:in:)`` to
    /// fall back cleanly.
    func disconnect(_ integration: Integration) {
        oauthService.clearTokens(for: integration.id)
        imapCredentialStore.clear(for: integration.id)
    }

    /// Marks `integration` as the active provider for `capability`, upserting
    /// the single selection row for that capability.
    func setActiveProvider(
        _ integration: Integration,
        for capability: Capability,
        in context: ModelContext
    ) {
        let descriptor = FetchDescriptor<CapabilityProviderSelection>()
        let existing = (try? context.fetch(descriptor))?
            .first { $0.capability == capability }
        if let existing {
            existing.integrationID = integration.id
            existing.sourceKind = .integration
            existing.updatedAt = .now
        } else {
            context.insert(CapabilityProviderSelection(
                capability: capability,
                integrationID: integration.id
            ))
        }
    }

    /// Removes any selection rows pointing at `integrationID`, so resolution
    /// falls back to the oldest remaining connected provider for capabilities
    /// that integration was the active choice for. Called when an integration
    /// is disconnected.
    func clearSelections(referencing integrationID: UUID, in context: ModelContext) {
        let descriptor = FetchDescriptor<CapabilityProviderSelection>()
        guard let selections = try? context.fetch(descriptor) else { return }
        for selection in selections where selection.integrationID == integrationID {
            context.delete(selection)
        }
    }

    /// A connected integration's provided capabilities that were actually granted.
    private func grantedCapabilities(
        of integration: Integration,
        type: IntegrationType
    ) -> Set<Capability> {
        type.providedCapabilities.filter { integration.grantedCapabilities.contains($0.rawValue) }
    }
}
