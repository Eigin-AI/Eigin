import Foundation

/// A human-facing grouping of integrations, used to browse them and to label
/// the connected list.
///
/// Presentation-only, with no persisted state. Membership is declared by each
/// ``IntegrationType/category``.
enum IntegrationCategory: String, CaseIterable, Identifiable, Sendable {
    case email
    case familyAndSchool
    /// What iOS gives permission for: Apple Health, Calendar, Reminders, Location.
    case platform
    case music

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .email: Localized.Integrations.Category.Email.displayName
        case .familyAndSchool: Localized.Integrations.Category.FamilyAndSchool.displayName
        case .platform: Localized.Integrations.Category.Platform.displayName
        case .music: Localized.Integrations.Category.Music.displayName
        }
    }

    /// Icon shown on the browse tile.
    // TODO: Switch to `Iconography` once it carries icons covering these categories.
    var systemImage: String {
        switch self {
        case .email: "envelope.fill"
        case .familyAndSchool: "figure.child"
        case .platform: "iphone"
        case .music: "music.note"
        }
    }
}

extension IntegrationCategory {
    /// Bundled integration types that belong to this category.
    var integrationTypes: [IntegrationType] {
        BundledIntegrationType.all.filter { $0.category == self }
    }

    /// Whether the category has at least one connectable provider. Those
    /// without one appear in the browse grid as disabled tiles.
    var isAvailable: Bool {
        !integrationTypes.isEmpty
    }

    /// Categories ordered for the browse grid, available ones first.
    static var browseOrder: [IntegrationCategory] {
        allCases.filter(\.isAvailable) + allCases.filter { !$0.isAvailable }
    }

    /// The category a capability is surfaced under, derived from whichever
    /// bundled type provides it — used for the connected-list section label.
    static func category(for capability: Capability) -> IntegrationCategory? {
        BundledIntegrationType.all
            .first { $0.providedCapabilities.contains(capability) }?.category
    }
}
