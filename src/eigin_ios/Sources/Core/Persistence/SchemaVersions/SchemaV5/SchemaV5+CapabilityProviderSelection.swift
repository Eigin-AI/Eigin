import Foundation
import SwiftData

extension SchemaV5 {
    /// The user's chosen active provider for a ``Capability``, when more than
    /// one connected integration provides it. One row per capability; absence
    /// means "use the default" active provider.
    @Model
    final class CapabilityProviderSelection {
        /// `Capability.rawValue`. Treated as the logical key for this row —
        /// enforced in code via `IntegrationManager.setActiveProvider`, not by
        /// a store-level unique constraint.
        var capabilityRaw: String
        /// `ProviderSourceKind.rawValue`. Only `.integration` is acted upon
        /// today; `.native` is reserved for a future OS-backed provider.
        var sourceKindRaw: String
        /// Set when `sourceKind == .integration`; `nil` for `.native`.
        var integrationID: UUID?
        var updatedAt: Date

        /// Typed accessor over `capabilityRaw`.
        var capability: Capability? {
            Capability(rawValue: capabilityRaw)
        }

        var sourceKind: ProviderSourceKind {
            get { ProviderSourceKind(rawValue: sourceKindRaw) ?? .integration }
            set { sourceKindRaw = newValue.rawValue }
        }

        init(
            capability: Capability,
            sourceKind: ProviderSourceKind = .integration,
            integrationID: UUID?
        ) {
            capabilityRaw = capability.rawValue
            sourceKindRaw = sourceKind.rawValue
            self.integrationID = integrationID
            updatedAt = .now
        }
    }
}
