import Factory
import Foundation

/// Turns connected, enabled ``Integration`` records into tools grouped by
/// ``Capability``, for ``ToolAssembly`` to gate behind active skills.
///
/// Unlike ``MCPServerManager``, there's no live connection to manage — tool
/// construction is synchronous, since ``EmailProvider`` (and future backends)
/// fetch tokens lazily per-call rather than at connect time.
@MainActor
final class IntegrationManager {
    private let oauthService: any IntegrationOAuthService

    init(oauthService: any IntegrationOAuthService) {
        self.oauthService = oauthService
    }

    /// Builds the capability → tools map for all connected, enabled integrations,
    /// restricted to capabilities each integration actually had granted — the
    /// same rule ``connectedCapabilities(integrations:)`` uses, so the two never
    /// disagree about what a given integration provides.
    func toolsByCapability(
        integrations: [Integration],
        context: ToolContext
    ) -> [Capability: [any Tool]] {
        var map: [Capability: [any Tool]] = [:]
        let ordered = integrations.sorted { $0.createdAt < $1.createdAt }
        for integration in ordered where integration.isEnabled {
            guard let type = BundledIntegrationType.type(forID: integration.typeID)
            else { continue }
            for capability in grantedCapabilities(of: integration, type: type) {
                // AddIntegration already blocks connecting a second integration
                // for a capability another connection provides, but that's a
                // single UI-level guard — defend here too, so two integrations
                // granting the same capability can never produce same-named
                // tools that would silently collide in `ToolRegistry` (last one
                // registered would otherwise win with no error). First
                // connected integration for a capability wins; later ones are
                // ignored for it.
                guard map[capability] == nil else { continue }
                map[capability] = type.makeTools(capability, integration, context)
            }
        }
        return map
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

    /// Disconnects an integration: clears its OAuth tokens and removes the model.
    /// Callers are responsible for deleting `integration` from the model context.
    func disconnect(_ integration: Integration) {
        oauthService.clearTokens(for: integration.id)
    }

    /// A connected integration's provided capabilities that were actually granted.
    private func grantedCapabilities(
        of integration: Integration,
        type: IntegrationType
    ) -> Set<Capability> {
        type.providedCapabilities.filter { integration.grantedCapabilities.contains($0.rawValue) }
    }
}
