import Foundation

/// A swappable area of behavior that integrations provide and skills consume.
///
/// Distinct from ``ToolCapability`` (the permission identity of a single
/// tool): a `Capability` is a behavior area — e.g. email — potentially
/// fulfilled by several tools and by more than one integration backend.
///
/// Skills declare the capabilities they need (``Skill/requiredCapabilities``);
/// integrations declare the capabilities they provide
/// (``IntegrationType/providedCapabilities``). A capability's tools are only
/// in context when both sides line up — see `ToolRegistry.chat`.
enum Capability: String, Codable, CaseIterable, Sendable {
    case email
    case aula

    /// The user-facing name, from the string catalog.
    var displayName: String {
        switch self {
        case .email: Localized.Capability.email
        case .aula: Localized.Capability.aula
        }
    }

    /// The permissions-UI category that tools providing this capability are
    /// grouped under. `nil` when the capability has no integration-backed
    /// category — those categories show in the permissions UI regardless of
    /// what's connected.
    var toolCategory: ToolCapability.Category? {
        switch self {
        case .email: .email
        case .aula: .familyAndSchool
        }
    }
}
