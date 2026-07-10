import Foundation

/// Where a capability's active provider comes from.
///
/// Only `.integration` is wired up today; `.native` is a reserved placeholder
/// so the persisted ``CapabilityProviderSelection`` schema doesn't need
/// reshaping if an OS-backed provider (e.g. a native calendar) lands later.
enum ProviderSourceKind: String, Codable, CaseIterable, Sendable {
    case integration
    case native
}
