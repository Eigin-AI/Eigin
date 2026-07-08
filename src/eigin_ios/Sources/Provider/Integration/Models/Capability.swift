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
}
